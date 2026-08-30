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
            '({ dict: typeof window.Dictionary, sched: typeof window.Scheduler, app: !!document.querySelector("#app"), words: document.querySelectorAll(".tab").length, cet6: window.CET6_WORDS_COUNT })'
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
              return { added, meaning, word, reviewVisible, feedbackVisible, books, activeBookName, newBookWords };
            })()`
          );
          console.log('SMOKE_RESULT ' + JSON.stringify({ ...result, query }));
          const ok =
            result.dict === 'object' &&
            result.sched === 'object' &&
            result.app === true &&
            result.words === 5 &&
            result.cet6 >= 1000 &&
            query.added === true &&
            query.meaning === true &&
            query.reviewVisible === true &&
            query.feedbackVisible === true &&
            query.books >= 2 &&
            query.activeBookName === '测试本' &&
            query.newBookWords === 1;
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
          await win.webContents.executeJavaScript(
            `(async () => {
              document.querySelector('#panel').classList.remove('hidden');
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

ipcMain.handle('set-ignore-mouse', (event, ignore) => {
  if (win && !win.isDestroyed()) {
    win.setIgnoreMouseEvents(!!ignore, { forward: true });
  }
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

ipcMain.handle('lookup-online', async (event, word) => {
  if (!word || !/^[a-zA-Z][a-zA-Z\-' ]*$/.test(word)) return null;
  try {
    const res = await fetchWithTimeout(
      'https://dict.youdao.com/jsonapi?q=' + encodeURIComponent(word.trim())
    );
    if (!res.ok) return null;
    const data = await res.json();
    const basic = data.basic || {};
    const explains = Array.isArray(basic.explains) ? basic.explains : [];
    const translation = Array.isArray(data.translation) ? data.translation : [];
    const phonetic = basic['us-phonetic'] || basic['uk-phonetic'] || basic.phonetic || '';
    if (!explains.length && !translation.length) return null;
    return {
      phonetic,
      meaning: explains.join('；') || translation.join('；'),
      source: 'youdao'
    };
  } catch (e) {
    return null;
  }
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
