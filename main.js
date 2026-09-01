const {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  clipboard,
  net,
  Tray,
  Menu,
  nativeImage
} = require('electron');
const path = require('path');
const fs = require('fs');

const DEFAULT_DATA = {
  books: [],
  stats: { days: {} },
  settings: {
    dailyQuota: 20,
    showExampleBeforeAnswer: true,
    firstReviewDelayMin: 60,
    activeBookId: ''
  }
};

let win = null;
let tray = null;
let dataFile = null;
let windowMode = 'panel';
// 拖动期间固定的窗口尺寸：Windows 透明无边框窗在 setPosition 时会把尺寸带偏（electron#10862），
// 导致拖动时面板被异常拉伸。这里在拖动开始时记住尺寸，移动时用 setBounds 固定尺寸，避免漂移。
let dragBounds = null;

const PET_W = 250;
const PET_H = 210;
const PANEL_W = 470;
const PANEL_H = 640;

function getDataFile() {
  if (!dataFile) dataFile = path.join(app.getPath('userData'), 'word-pet-data.json');
  return dataFile;
}

function loadData() {
  try {
    const raw = fs.readFileSync(getDataFile(), 'utf8');
    const data = JSON.parse(raw);
    let books = [];
    if (Array.isArray(data.books)) {
      books = data.books;
    } else if (Array.isArray(data.words)) {
      // 兼容旧版本：把旧单词表迁移为默认词汇本
      books = [
        {
          id: 'book-default',
          name: '默认词汇本',
          description: '由旧版本数据迁移',
          builtin: false,
          createdAt: Date.now(),
          words: data.words
        }
      ];
    }
    return {
      books,
      stats: data.stats && typeof data.stats === 'object' ? data.stats : { days: {} },
      settings: Object.assign({}, DEFAULT_DATA.settings, data.settings || {})
    };
  } catch (e) {
    return JSON.parse(JSON.stringify(DEFAULT_DATA));
  }
}

function saveData(data) {
  try {
    fs.mkdirSync(path.dirname(getDataFile()), { recursive: true });
    fs.writeFileSync(getDataFile(), JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (e) {
    return false;
  }
}

function summon() {
  if (!win) return;
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
  win.webContents.send('shortcut-summon');
}

function togglePet() {
  if (!win) return;
  if (win.isVisible()) {
    win.hide();
  } else {
    win.show();
    win.focus();
    win.webContents.send('pet-shown');
  }
}

function setWindowMode(mode) {
  if (!win || win.isDestroyed()) return;
  if (mode === windowMode) return;
  windowMode = mode;
  if (mode === 'panel') {
    const [x, y] = win.getPosition();
    win.setBounds({ x: Math.round(x - (PANEL_W - PET_W) / 2), y, width: PANEL_W, height: PANEL_H });
  } else {
    const [x, y] = win.getPosition();
    win.setBounds({ x: Math.round(x + (PANEL_W - PET_W) / 2), y, width: PET_W, height: PET_H });
  }
}

function createWindow() {
  win = new BrowserWindow({
    width: 470,
    height: 640,
    transparent: true,
    frame: false,
    resizable: false,
    alwaysOnTop: true,
    hasShadow: false,
    skipTaskbar: false,
    backgroundColor: '#00000000',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));

  if (process.argv.includes('--smoke-test')) {
    win.webContents.on('console-message', (event) => {
      if (event.level === 'error') console.error('[renderer]', event.message);
    });
    win.webContents.on('did-finish-load', () => {
      setTimeout(async () => {
        try {
          const result = await win.webContents.executeJavaScript(
            '({ dict: typeof window.Dictionary, sched: typeof window.Scheduler, app: !!document.querySelector("#app"), words: document.querySelectorAll(".tab").length, cet6: window.CET6_WORDS_COUNT, dictCount: window.Dictionary.wordCount() })'
          );
          const query = await win.webContents.executeJavaScript(
            `(async () => {
              const input = document.querySelector('#query-input');
              input.value = 'abandon';
              document.querySelector('#query-btn').click();
              await new Promise(r => setTimeout(r, 900));
              const res = document.querySelector('#query-result').innerText || '';
              const added = res.includes('已加入单词本');
              const meaning = res.includes('放弃');
              window.__petDebug.setDue('abandon');
              await new Promise(r => setTimeout(r, 200));
              const word = (document.querySelector('#review-word') || {}).textContent || '';
              const reviewVisible = !document.querySelector('#review-card').classList.contains('hidden');
              const answer = document.querySelector('#review-answer');
              answer.value = '放弃；抛弃';
              document.querySelector('#review-submit').click();
              await new Promise(r => setTimeout(r, 100));
              const feedbackVisible = !document.querySelector('#review-feedback').classList.contains('hidden');
              const ratingBtn = document.querySelector('#rating-buttons .rating-btn');
              if (ratingBtn) ratingBtn.click();
              await new Promise(r => setTimeout(r, 500));
              // 词汇本：新建并切换到新本，然后查词
              document.querySelector('#btn-new-book').click();
              document.querySelector('#book-name').value = '测试本';
              document.querySelector('#book-create').click();
              await new Promise(r => setTimeout(r, 150));
              const books = window.__petDebug.getData().books.length;
              const activeBookName = window.__petDebug.currentBook().name;
              document.querySelector('.tab[data-tab="query"]').click();
              const input2 = document.querySelector('#query-input');
              input2.value = 'abundant';
              document.querySelector('#query-btn').click();
              await new Promise(r => setTimeout(r, 700));
              const newBookWords = window.__petDebug.currentBook().words.length;
              // 查询 CET6 词但不在示例词库中：验证完整离线词典命中
              const input3 = document.querySelector('#query-input');
              input3.value = 'abide';
              input3.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
              await new Promise(r => setTimeout(r, 700));
              const abideText = document.querySelector('#query-result').innerText || '';
              const offlineHit = abideText.includes('遵守') && abideText.includes('离线词库');
              const wordsAfterAbide = window.__petDebug.currentBook().words.length;
              // 缓存命中场景：词在本地缓存，应能进入当前词汇本并显示结果
              window.Dictionary.cacheWord('zzunique', { meaning: '测试释义', phonetic: '' });
              const input4 = document.querySelector('#query-input');
              input4.value = 'zzunique';
              document.querySelector('#query-btn').click();
              await new Promise(r => setTimeout(r, 500));
              const cacheText = document.querySelector('#query-result').innerText || '';
              const cacheAdded =
                window.__petDebug.currentBook().words.some((w) => w.word === 'zzunique') &&
                cacheText.includes('测试释义') &&
                cacheText.includes('本地缓存');
              // 在内置六级词汇本中查询已存在的 CET6 词，验证显示会更新为当前词
              const builtinId = window.__petDebug.getData().books.find((b) => b.builtinCET6).id;
              const bookSelect = document.querySelector('#book-select');
              bookSelect.value = builtinId;
              bookSelect.dispatchEvent(new Event('change'));
              await new Promise(r => setTimeout(r, 150));
              const input5 = document.querySelector('#query-input');
              input5.value = 'abide';
              input5.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
              await new Promise(r => setTimeout(r, 500));
              const builtinText = document.querySelector('#query-result').innerText || '';
              const builtinDisplayOk = builtinText.includes('查询：abide') && builtinText.includes('abide');
              return { added, meaning, word, reviewVisible, feedbackVisible, books, activeBookName, newBookWords, offlineHit, wordsAfterAbide, cacheAdded, builtinDisplayOk };
            })()`
          );
          console.log('SMOKE_RESULT ' + JSON.stringify({ ...result, query }));
          const ok =
            result.dict === 'object' &&
            result.sched === 'object' &&
            result.app === true &&
            result.words === 5 &&
            result.cet6 >= 1000 &&
            result.dictCount >= 5000 &&
            query.added === true &&
            query.meaning === true &&
            query.reviewVisible === true &&
            query.feedbackVisible === true &&
            query.books >= 2 &&
            query.activeBookName === '测试本' &&
            query.newBookWords === 1 &&
            query.offlineHit === true &&
            query.wordsAfterAbide === 2 &&
            query.cacheAdded === true &&
            query.builtinDisplayOk === true;
          console.log(ok ? 'SMOKE_OK' : 'SMOKE_FAIL');
          app.exit(ok ? 0 : 1);
        } catch (e) {
          console.error('SMOKE_ERROR', e);
          app.exit(1);
        }
      }, 1200);
    });
  }

  if (process.argv.includes('--screenshot')) {
    const outPath = process.argv[process.argv.indexOf('--screenshot') + 1] || 'screenshot.png';
    win.webContents.on('did-finish-load', () => {
      setTimeout(async () => {
        try {
          // 先截宠物模式（含快捷键气泡），再展开面板
          const petImage = await win.webContents.capturePage();
          const petPath = outPath.replace(/\.png$/i, '-pet.png');
          require('fs').writeFileSync(path.join(__dirname, petPath), petImage.toPNG());
          console.log('SCREENSHOT_SAVED ' + petPath);
          await win.webContents.executeJavaScript(
            `(async () => {
              window.__petDebug.openPanel();
              document.querySelector('.tab[data-tab="query"]').click();
              const input = document.querySelector('#query-input');
              input.value = 'abandon';
              document.querySelector('#query-btn').click();
              await new Promise(r => setTimeout(r, 700));
            })()`
          );
          const image = await win.webContents.capturePage();
          require('fs').writeFileSync(path.join(__dirname, outPath), image.toPNG());
          console.log('SCREENSHOT_SAVED ' + outPath);
          await win.webContents.executeJavaScript(
            `(async () => {
              window.__petDebug.setDue('abandon');
              document.querySelector('.tab[data-tab="review"]').click();
              await new Promise(r => setTimeout(r, 400));
            })()`
          );
          const reviewImage = await win.webContents.capturePage();
          const reviewPath = outPath.replace(/\.png$/i, '-review.png');
          require('fs').writeFileSync(path.join(__dirname, reviewPath), reviewImage.toPNG());
          console.log('SCREENSHOT_SAVED ' + reviewPath);
          await win.webContents.executeJavaScript(
            `(async () => {
              document.querySelector('.tab[data-tab="words"]').click();
              await new Promise(r => setTimeout(r, 300));
            })()`
          );
          const wordsImage = await win.webContents.capturePage();
          const wordsPath = outPath.replace(/\.png$/i, '-words.png');
          require('fs').writeFileSync(path.join(__dirname, wordsPath), wordsImage.toPNG());
          console.log('SCREENSHOT_SAVED ' + wordsPath);
          app.exit(0);
        } catch (e) {
          console.error('SCREENSHOT_ERROR', e);
          app.exit(1);
        }
      }, 1200);
    });
  }
}

function createTray() {
  const iconPath = path.join(__dirname, 'assets', 'tray-icon.png');
  let icon;
  try {
    icon = nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 });
  } catch (e) {
    icon = nativeImage.createEmpty();
  }
  tray = new Tray(icon);
  tray.setToolTip('单词桌宠');
  const menu = Menu.buildFromTemplate([
    { label: '呼出输入栏（Alt+W）', click: summon },
    { label: '显示 / 隐藏桌宠（Alt+P）', click: togglePet },
    { type: 'separator' },
    { label: '退出', click: () => app.quit() }
  ]);
  tray.setContextMenu(menu);
  tray.on('click', summon);
}

function registerShortcuts() {
  globalShortcut.register('Alt+W', summon);
  globalShortcut.register('Alt+E', () => {
    if (win) win.webContents.send('shortcut-hide-panel');
  });
  globalShortcut.register('Alt+P', togglePet);
}

app.whenReady().then(() => {
  createWindow();
  createTray();
  registerShortcuts();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

/* ---------------- IPC ---------------- */

ipcMain.handle('get-clipboard', () => {
  try { return clipboard.readText() || ''; } catch (e) { return ''; }
});

ipcMain.handle('load-data', () => loadData());

ipcMain.handle('save-data', (event, data) => saveData(data));

ipcMain.handle('window-hide', () => {
  if (win) { win.hide(); return true; }
  return false;
});

ipcMain.handle('set-window-mode', (event, mode) => {
  setWindowMode(mode);
  return true;
});

ipcMain.handle('get-window-position', () => {
  if (win && !win.isDestroyed()) return win.getPosition();
  return [0, 0];
});

ipcMain.handle('set-window-position', (event, x, y) => {
  if (win && !win.isDestroyed()) {
    // 用 setBounds 并固定拖动开始时的尺寸，而非 setPosition。
    // setPosition 内部会重读 GetSize()，在 Windows 高 DPI 下每次都会让尺寸持续增大。
    if (dragBounds) {
      win.setBounds({ x: Math.round(x), y: Math.round(y), width: dragBounds.width, height: dragBounds.height });
    } else {
      const b = win.getBounds();
      win.setBounds({ x: Math.round(x), y: Math.round(y), width: b.width, height: b.height });
    }
  }
  return true;
});

ipcMain.handle('begin-window-drag', () => {
  if (win && !win.isDestroyed()) {
    const b = win.getBounds();
    dragBounds = { width: b.width, height: b.height };
  } else {
    dragBounds = null;
  }
  return true;
});

ipcMain.handle('end-window-drag', () => {
  dragBounds = null;
  return true;
});

ipcMain.handle('get-auto-launch', () => {
  try { return app.getLoginItemSettings().openAtLogin; } catch (e) { return false; }
});

ipcMain.handle('set-auto-launch', (event, enabled) => {
  try {
    app.setLoginItemSettings({ openAtLogin: !!enabled });
    return app.getLoginItemSettings().openAtLogin;
  } catch (e) {
    return false;
  }
});

function fetchWithTimeout(url, ms = 8000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  return net.fetch(url, { signal: controller.signal }).finally(() => clearTimeout(timer));
}

/* 解析有道 jsonapi 新版中文释义（ec 结构） */
function youdaoEcMeanings(ec) {
  const out = [];
  if (!ec || !Array.isArray(ec.word)) return out;
  for (const w of ec.word) {
    const trs = Array.isArray(w.trs) ? w.trs : [];
    for (const t of trs) {
      const items = Array.isArray(t.tr) ? t.tr : [];
      for (const item of items) {
        const l = item && item.l;
        const lines = Array.isArray(l && l.i) ? l.i : [];
        for (const s of lines) {
          if (s && !/^【名】.*（人名）/.test(s)) out.push(String(s).trim());
        }
      }
    }
  }
  return [...new Set(out)];
}

/* 有道 jsonapi 英文释义兜底（ee 结构，WordNet） */
function youdaoEeMeanings(ee) {
  const out = [];
  if (!ee || !ee.word || !Array.isArray(ee.word.trs)) return out;
  for (const t of ee.word.trs) {
    const pos = t.pos || '';
    const tr = Array.isArray(t.tr) ? t.tr : [];
    for (const item of tr) {
      const i = item && item.l && item.l.i;
      if (i) out.push((pos ? pos + ' ' : '') + String(i));
    }
  }
  return [...new Set(out)];
}

/* 机器翻译只有当结果确实翻译成了中文、且不是原词时才可信 */
function looksLikeChineseTranslation(text, word) {
  const t = String(text || '').trim();
  if (!t || !/[\u4e00-\u9fa5]/.test(t)) return false;
  const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  return norm(t) !== norm(word) && t.toLowerCase() !== word.toLowerCase();
}

ipcMain.handle('lookup-online', async (event, word) => {
  const q = String(word || '').trim();
  if (!q || !/^[a-zA-Z][a-zA-Z\-' ]*$/.test(q)) return null;

  // 1) 有道词典（中文释义 + 音标；新版接口返回 ec/simple 结构）
  try {
    const res = await fetchWithTimeout('https://dict.youdao.com/jsonapi?q=' + encodeURIComponent(q));
    if (res.ok) {
      const data = await res.json();
      const basic = data.basic || {};
      const explains = Array.isArray(basic.explains) ? basic.explains : [];
      const translation = Array.isArray(data.translation) ? data.translation : [];
      const ecMeanings = youdaoEcMeanings(data.ec);
      const meanings = ecMeanings.concat(explains, translation).filter(Boolean);
      const simpleWord = data.simple && data.simple.word && data.simple.word[0];
      const phonetic =
        (simpleWord && (simpleWord.usphone || simpleWord.ukphone)) ||
        basic['us-phonetic'] || basic['uk-phonetic'] || basic.phonetic || '';
      if (meanings.length) {
        return {
          phonetic,
          meaning: meanings.join('；'),
          source: 'youdao'
        };
      }
      // 没有中文释义时，退回英文释义（WordNet）也远好于机器翻译乱译
      const eeMeanings = youdaoEeMeanings(data.ee);
      if (eeMeanings.length) {
        return { phonetic, meaning: eeMeanings.join('；'), source: 'youdao-ee' };
      }
    }
  } catch (e) {
    /* 尝试下一个源 */
  }

  // 2) MyMemory 整词翻译（英 → 中）：只接受真正翻译成中文、且不是原词的文本
  try {
    const m = await fetchWithTimeout(
      'https://api.mymemory.translated.net/get?q=' + encodeURIComponent(q) + '&langpair=en|zh-CN'
    );
    if (m.ok) {
      const data = await m.json();
      const translated = data && data.responseData && data.responseData.translatedText;
      if (looksLikeChineseTranslation(translated, q)) {
        return { phonetic: '', meaning: translated, source: 'mymemory' };
      }
    }
  } catch (e) {
    /* 尝试下一个源 */
  }

  // 3) Free Dictionary API（英文释义兜底）
  try {
    const res = await fetchWithTimeout(
      'https://api.dictionaryapi.dev/api/v2/entries/en/' + encodeURIComponent(q)
    );
    if (res.ok) {
      const data = await res.json();
      const entry = Array.isArray(data) ? data[0] : null;
      const defs = [];
      if (entry && Array.isArray(entry.meanings)) {
        entry.meanings.forEach((m) => {
          (m.definitions || []).slice(0, 3).forEach((d) => {
            if (d.definition) defs.push(d.definition);
          });
        });
      }
      if (defs.length) {
        const phonetic =
          (entry && (entry.phonetic || (entry.phonetics && entry.phonetics[0] && entry.phonetics[0].text))) || '';
        return { phonetic, meaning: defs.join('；'), source: 'dictionaryapi' };
      }
    }
  } catch (e) {
    /* 全部失败 */
  }

  return null;
});

ipcMain.handle('translate-text', async (event, text) => {
  if (!text || text.length > 2000) return null;
  try {
    const url =
      'https://api.mymemory.translated.net/get?q=' +
      encodeURIComponent(text) +
      '&langpair=en|zh-CN';
    const res = await fetchWithTimeout(url);
    if (!res.ok) return null;
    const data = await res.json();
    const translated = data && data.responseData && data.responseData.translatedText;
    return translated || null;
  } catch (e) {
    return null;
  }
});
