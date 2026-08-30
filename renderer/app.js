(function () {
  'use strict';

  const $ = (sel) => document.querySelector(sel);

  /* ---------------- 桌宠素材映射 ---------------- */

  const PET = {
    idle: ['工作ing.gif', '休息ing.gif', '小手机真好玩.gif', '思考ing.gif'],
    summon: '突然出现~.gif',
    thinking: '思考ing.gif',
    recording: '在帮主人记录ing.gif',
    success: '主人好厉害！.gif',
    complete: '顺利完成~.gif',
    love: '最喜欢主人了~.gif',
    encourage: '主人加油呀~.gif',
    calm: '别太紧张啦~.gif',
    tired: '工作做晕了.gif',
    eat: '该吃饭了.gif'
  };

  const IDLE_BUBBLES = [
    '在陪你记单词～',
    '今天也一起加油～',
    '累了就休息一下下',
    '有生词随时叫我！',
    '我刚看了一眼，你很棒！'
  ];

  const petAsset = (name) => '../素材/' + encodeURIComponent(name);

  let petBubbleTimer = null;
  function setPet(state, bubble, duration) {
    const list = PET[state] || PET.idle;
    const name = Array.isArray(list) ? list[Math.floor(Math.random() * list.length)] : list;
    const img = $('#pet-img');
    if (img) img.src = petAsset(name);
    const el = $('#pet-bubble');
    if (!el) return;
    if (bubble) {
      el.textContent = bubble;
      el.classList.remove('hidden');
      clearTimeout(petBubbleTimer);
      petBubbleTimer = setTimeout(() => el.classList.add('hidden'), duration || 3200);
    }
  }

  /* ---------------- 数据 ---------------- */

  const DEFAULTS = {
    books: [],
    stats: { days: {} },
    settings: {
      dailyQuota: 20,
      showExampleBeforeAnswer: true,
      firstReviewDelayMin: 60,
      activeBookId: ''
    }
  };

  let data = null;
  let saveTimer = null;
  let currentTab = 'query';
  let querySeq = 0;
  let reviewQueue = [];
  let currentReview = null;
  let editingId = null;

  function cloneDefaults() {
    return JSON.parse(JSON.stringify(DEFAULTS));
  }

  async function loadData() {
    if (window.petAPI) {
      try { return await window.petAPI.loadData(); } catch (e) { /* fallthrough */ }
    }
    try {
      const raw = localStorage.getItem('word-pet-data');
      return raw ? JSON.parse(raw) : cloneDefaults();
    } catch (e) {
      return cloneDefaults();
    }
  }

  async function saveNow() {
    if (window.petAPI) {
      try { await window.petAPI.saveData(data); } catch (e) { /* ignore */ }
    } else {
      try { localStorage.setItem('word-pet-data', JSON.stringify(data)); } catch (e) { /* ignore */ }
    }
  }

  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveNow, 350);
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  const SOURCE_LABELS = {
    offline: '离线词库（5760 词）',
    cache: '本地缓存',
    book: '已有词汇本',
    youdao: '在线 · 有道',
    mymemory: '在线 · 翻译',
    dictionaryapi: '在线 · 英文释义'
  };

  function sourceLabel(src) {
    return SOURCE_LABELS[src] || src || '未知';
  }

  /* ---------------- 词汇本 ---------------- */

  function makeSeedWord(row, idx) {
    const word = String(row && row[0] ? row[0] : '').toLowerCase();
    const meaning = row && row[1] ? String(row[1]) : '';
    const phonetic = row && row[2] ? String(row[2]) : '';
    const w = {
      id: 'cet6-' + idx,
      word: word,
      meaning: meaning,
      phonetic: phonetic,
      examples: [],
      tags: ['六级'],
      createdAt: Date.now(),
      mastered: false
    };
    Object.assign(w, window.Scheduler.newWordBase(Date.now() + (data.settings.firstReviewDelayMin || 60) * 60 * 1000));
    return w;
  }

  function migrateAndEnsureBooks() {
    if (!Array.isArray(data.books) || data.books.length === 0) {
      const oldWords = Array.isArray(data.words) ? data.words : [];
      data.books = [
        {
          id: 'book-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
          name: '我的单词本',
          description: '自定义词汇本',
          builtin: false,
          createdAt: Date.now(),
          words: oldWords
        }
      ];
      delete data.words;
    }

    // 内置六级词汇本（只创建一次）
    if (!data.books.some((b) => b.builtinCET6)) {
      const rows = window.CET6_WORDS || [];
      const words = rows.map((row, i) => makeSeedWord(row, i));
      data.books.unshift({
        id: 'book-cet6',
        name: '六级词汇 · 内置',
        description: '内置 CET-6 词表（' + (window.CET6_WORDS_COUNT || words.length) + ' 词）',
        builtin: true,
        builtinCET6: true,
        createdAt: Date.now(),
        words: words
      });
    }

    // 内置四级词汇本（只创建一次）
    if (!data.books.some((b) => b.builtinCET4)) {
      const rows = window.CET4_WORDS || [];
      const words = rows.map((row, i) => makeSeedWord(row, i));
      data.books.unshift({
        id: 'book-cet4',
        name: '四级词汇 · 内置',
        description: '内置 CET-4 词表（' + (window.CET4_WORDS_COUNT || words.length) + ' 词）',
        builtin: true,
        builtinCET4: true,
        createdAt: Date.now(),
        words: words
      });
    }

    if (!data.settings.activeBookId || !data.books.some((b) => b.id === data.settings.activeBookId)) {
      data.settings.activeBookId = data.books[0].id;
    }
  }

  function currentBook() {
    const book = data.books.find((b) => b.id === data.settings.activeBookId) || data.books[0];
    // 防御：旧/损坏数据中缺少 words 数组时补上，避免查询"假成功"
    if (book && !Array.isArray(book.words)) book.words = [];
    return book;
  }

  function currentWords() {
    const book = currentBook();
    return book && Array.isArray(book.words) ? book.words : [];
  }

  /* ---------------- 联网兜底 ---------------- */

  async function onlineLookup(word) {
    if (window.petAPI) {
      try { return await window.petAPI.lookupOnline(word); } catch (e) { return null; }
    }
    try {
      const res = await fetch('https://dict.youdao.com/jsonapi?q=' + encodeURIComponent(word));
      if (!res.ok) return null;
      const d = await res.json();
      const basic = d.basic || {};
      const explains = Array.isArray(basic.explains) ? basic.explains : [];
      const trans = Array.isArray(d.translation) ? d.translation : [];
      if (!explains.length && !trans.length) return null;
      return { word: word.toLowerCase(), meaning: explains.join('；') || trans.join('；'), phonetic: '', source: 'youdao' };
    } catch (e) {
      return null;
    }
  }

  async function translateText(text) {
    if (window.petAPI) {
      try { return await window.petAPI.translateText(text); } catch (e) { return null; }
    }
    try {
      const res = await fetch(
        'https://api.mymemory.translated.net/get?q=' + encodeURIComponent(text) + '&langpair=en|zh-CN'
      );
      if (!res.ok) return null;
      const d = await res.json();
      return (d && d.responseData && d.responseData.translatedText) || null;
    } catch (e) {
      return null;
    }
  }

  async function getClipboard() {
    if (window.petAPI) {
      try { return (await window.petAPI.getClipboard()) || ''; } catch (e) { return ''; }
    }
    return '';
  }

  async function getAutoLaunch() {
    if (window.petAPI) {
      try { return !!(await window.petAPI.getAutoLaunch()); } catch (e) { return false; }
    }
    return false;
  }

  async function setAutoLaunch(enabled) {
    if (window.petAPI) {
      try { return !!(await window.petAPI.setAutoLaunch(enabled)); } catch (e) { return false; }
    }
    return false;
  }

  /* ---------------- 例句匹配 ---------------- */

  function findExampleSentence(clip, word) {
    if (!clip) return null;
    const lower = String(clip).toLowerCase();
    const w = String(word).toLowerCase();
    if (!lower.includes(w)) return null;
    const parts = String(clip).split(/(?<=[.!?。！？])\s+/);
    const sentences = parts.map((s) => s.trim()).filter((s) => s.toLowerCase().includes(w));
    if (!sentences.length) return null;
    sentences.sort((a, b) => a.length - b.length);
    let s = sentences[0];
    if (s.length > 300) s = s.slice(0, 300).trimEnd() + '...';
    return s;
  }

  /* ---------------- 查词 ---------------- */

  async function handleQuery() {
    const input = $('#query-input');
    const word = input.value.trim();
    if (!word) return;
    const seq = ++querySeq;

    setPet('thinking', '帮你查一下～');

    let info = window.Dictionary.lookupWord(word);
    if (!info) {
      // 兜底：任何词汇本里已经收录过的词，直接用已有释义
      const key = String(word).toLowerCase();
      const fromBook = data.books.reduce(
        (acc, b) => acc || (b.words || []).find((w) => w.word.toLowerCase() === key),
        null
      );
      if (fromBook) {
        info = {
          word: fromBook.word,
          meaning: fromBook.meaning,
          phonetic: fromBook.phonetic || '',
          source: 'book'
        };
      }
    }
    if (!info) {
      info = await onlineLookup(word);
      if (info) window.Dictionary.cacheWord(word, info);
    }
    // 在线查询（有道/翻译/英文释义）返回的结果可能不含 word 字段，
    // 补齐当前查询词，避免入库 key 变成 "undefined"、显示成上一次查的词。
    if (info && !info.word) {
      info = Object.assign({}, info, { word: String(word).toLowerCase() });
    }

    if (!info) {
      if (seq !== querySeq) return;
      $('#query-result').innerHTML =
        '<div class="query-word-header">🔍 查询：' + escapeHtml(word) + '</div>' +
        '<div class="error-box">没有找到「' + escapeHtml(word) + '」的释义。' +
        '离线词典（5760 词）未命中，在线查询也失败（可能无网络或服务不可用）。<br>' +
        '你可以：检查网络后重试，或在“单词本 → 导入”中导入更完整的词表。</div>';
      setPet('calm', '这个词暂时没查到…');
      if (input.value.trim() === word) input.value = '';
      return;
    }

    let example = null;
    const useClipboard = $('#query-use-clipboard').checked;
    if (useClipboard) {
      const clip = await getClipboard();
      const sentence = findExampleSentence(clip, word);
      if (sentence) {
        setPet('recording', '找到原文了，记录中…');
        const trans = await translateText(sentence);
        example = { text: sentence, translation: trans || '', source: '剪贴板' };
      }
    }

    let record;
    try {
      record = addOrUpdateWord(info, example);
      saveNow(); // 立即写入磁盘，避免快速关窗导致单词丢失
    } catch (err) {
      if (seq !== querySeq) return;
      $('#query-result').innerHTML =
        '<div class="query-word-header">🔍 查询：' + escapeHtml(word) + '</div>' +
        '<div class="error-box">保存到单词本失败：' + escapeHtml((err && err.message) || String(err)) + '</div>';
      setPet('calm', '保存失败，稍后再试');
      if (input.value.trim() === word) input.value = '';
      return;
    }

    // 如果期间又发起了新查询，旧结果不再渲染，避免覆盖新结果
    if (seq !== querySeq) return;

    const exampleHtml = example
      ? '<div class="example-box"><div class="ex-text">📄 ' + escapeHtml(example.text) + '</div>' +
        (example.translation
          ? '<div class="ex-trans">译文：' + escapeHtml(example.translation) + '</div>'
          : '<div class="ex-trans">译文待补（离线或无网络）</div>') +
        '<div class="result-source">来源：' + escapeHtml(example.source) + '</div></div>'
      : '';

    const existingNote = record._existed ? '（该词已在当前词汇本中）' : '';
    $('#query-result').innerHTML =
      '<div class="query-word-header">🔍 查询：' + escapeHtml(word) + '</div>' +
      '<div class="result-card">' +
      '<div class="result-word">' + escapeHtml(record.word) + '</div>' +
      (record.phonetic ? '<div class="result-phonetic">' + escapeHtml(record.phonetic) + '</div>' : '') +
      '<div class="result-meaning">' + escapeHtml(record.meaning) + '</div>' +
      '<div class="result-source">来源：' + escapeHtml(sourceLabel(info.source)) + '</div>' +
      exampleHtml +
      '<div class="notice">✅ 已加入单词本（' + escapeHtml(currentBook().name) + '）' + existingNote + '</div>' +
      '</div>';

    setPet('success', '已记进单词本啦！');
    if (input.value.trim() === word) input.value = '';
  }

  function addOrUpdateWord(info, example) {
    const key = String(info.word).toLowerCase();
    const words = currentWords();
    const existing = words.find((w) => w.word.toLowerCase() === key);
    if (existing) {
      if (example) {
        const hasSame = existing.examples.some((e) => e.text === example.text);
        if (!hasSame) existing.examples.push(example);
      }
      existing._existed = true;
      return existing;
    }
    const word = {
      id: 'w' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7),
      word: key,
      meaning: info.meaning || '',
      phonetic: info.phonetic || '',
      examples: example ? [example] : [],
      tags: [],
      createdAt: Date.now(),
      mastered: false,
      _existed: false
    };
    Object.assign(word, window.Scheduler.newWordBase(Date.now() + (data.settings.firstReviewDelayMin || 60) * 60 * 1000));
    words.unshift(word);
    window.Scheduler.updateDailyStats(data.stats, 'add', { added: 1 });
    return word;
  }

  /* ---------------- 复习 ---------------- */

  function refreshReview() {
    const dueAll = window.Scheduler.dueWords(currentWords());
    const quota = Math.max(1, Math.min(200, Number(data.settings.dailyQuota) || 20));
    reviewQueue = dueAll.slice(0, quota);
    const empty = !reviewQueue.length;
    $('#review-empty').classList.toggle('hidden', !empty);
    $('#review-card').classList.toggle('hidden', empty);
    $('#review-done').classList.add('hidden');
    if (!empty) {
      nextReview();
    } else {
      currentReview = null;
    }
    renderStats();
  }

  function nextReview() {
    if (!reviewQueue.length) {
      currentReview = null;
      $('#review-card').classList.add('hidden');
      $('#review-empty').classList.add('hidden');
      $('#review-done').classList.remove('hidden');
      $('#review-done-info').textContent =
        '今天已完成 ' + window.Scheduler.computeTodayStats(data.stats).reviewed + ' 次复习。';
      setPet('complete', '今天的复习全部完成～');
      renderStats();
      return;
    }
    currentReview = reviewQueue.shift();
    $('#review-word').textContent = currentReview.word;
    const ex = currentReview.examples && currentReview.examples[0];
    const showEx = data.settings.showExampleBeforeAnswer && ex;
    $('#review-example').textContent = ex ? ex.text : '';
    $('#review-example').classList.toggle('hidden', !showEx);
    $('#review-answer').value = '';
    $('#review-answer').disabled = false;
    $('#review-submit').disabled = false;
    $('#review-feedback').classList.add('hidden');
    $('#review-answer').focus();
  }

  function submitReviewAnswer() {
    if (!currentReview) return;
    const answer = $('#review-answer').value.trim();
    $('#feedback-meaning').textContent =
      currentReview.meaning + (answer ? '　（你写的：' + answer + '）' : '');
    const ex = currentReview.examples && currentReview.examples[0];
    if (ex) {
      $('#feedback-example-text').textContent = ex.text;
      $('#feedback-example-trans').textContent = ex.translation ? '译文：' + ex.translation : '译文待补';
      $('#feedback-example').classList.remove('hidden');
    } else {
      $('#feedback-example').classList.add('hidden');
    }
    $('#review-feedback').classList.remove('hidden');
    $('#review-submit').disabled = true;
    $('#review-answer').disabled = true;
    buildRatingButtons();
  }

  function buildRatingButtons() {
    const box = $('#rating-buttons');
    box.innerHTML = '';
    for (let i = 0; i <= 10; i++) {
      const btn = document.createElement('button');
      btn.className = 'rating-btn';
      btn.textContent = String(i);
      btn.title = i <= 1 ? '完全不会' : i <= 3 ? '模糊' : i <= 5 ? '勉强' : i <= 7 ? '记得' : '轻松';
      btn.addEventListener('click', () => gradeReview(i));
      box.appendChild(btn);
    }
  }

  function gradeReview(rating) {
    if (!currentReview) return;
    window.Scheduler.rateWord(currentReview, rating);
    window.Scheduler.updateDailyStats(data.stats, 'review', { reviewed: 1, rating });
    scheduleSave();
    setPet(
      rating >= 8 ? 'success' : rating >= 5 ? 'encourage' : 'calm',
      rating >= 8 ? '太厉害了！' : rating >= 5 ? '不错，继续加油～' : '没关系，我陪你多记几次'
    );
    setTimeout(nextReview, 380);
  }

  function skipReview() {
    if (!currentReview) return;
    currentReview.nextReview = Date.now() + 30 * 60 * 1000;
    scheduleSave();
    setTimeout(nextReview, 150);
  }

  function markKnown() {
    if (!currentReview) return;
    currentReview.mastered = true;
    currentReview.nextReview = Date.now() + 30 * 24 * 60 * 60 * 1000;
    scheduleSave();
    setPet('success', '这个词已经掌握啦～');
    setTimeout(nextReview, 150);
  }

  /* ---------------- 词汇本 UI ---------------- */

  function renderBookSelect() {
    const select = $('#book-select');
    select.innerHTML = data.books
      .map(
        (b) =>
          '<option value="' + escapeHtml(b.id) + '">' +
          escapeHtml(b.name) + '（' + (b.words ? b.words.length : 0) + '）' +
          '</option>'
      )
      .join('');
    const book = currentBook();
    select.value = book.id;
    $('#active-book-info').textContent =
      '当前词汇本：' + book.name +
      ' · ' + (book.words ? book.words.length : 0) + ' 词' +
      (book.builtin ? ' · 内置' : '');
  }

  function openBookModal() {
    $('#book-name').value = '';
    $('#book-modal').classList.remove('hidden');
    $('#book-name').focus();
  }

  function closeBookModal() {
    $('#book-modal').classList.add('hidden');
  }

  function createBook() {
    const name = $('#book-name').value.trim();
    if (!name) {
      alert('请输入词汇本名称');
      return;
    }
    const book = {
      id: 'book-' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      name: name,
      description: '自定义词汇本',
      builtin: false,
      createdAt: Date.now(),
      words: []
    };
    data.books.push(book);
    data.settings.activeBookId = book.id;
    scheduleSave();
    closeBookModal();
    renderAll();
    switchTab('words');
  }

  function deleteBook() {
    const book = currentBook();
    if (!book) return;
    if (book.builtin) {
      alert('内置词汇本（' + book.name + '）不可删除。');
      return;
    }
    if (data.books.length <= 1) {
      alert('至少需要保留一个词汇本。');
      return;
    }
    if (!confirm('确定删除词汇本「' + book.name + '」？（含其中 ' + book.words.length + ' 个单词，不可恢复）')) return;
    data.books = data.books.filter((b) => b.id !== book.id);
    if (data.settings.activeBookId === book.id || !data.books.some((b) => b.id === data.settings.activeBookId)) {
      data.settings.activeBookId = data.books[0].id;
    }
    scheduleSave();
    renderAll();
    switchTab('words');
  }

  /* ---------------- 单词本 ---------------- */

  function renderWords() {
    renderBookSelect();
    const q = ($('#words-search').value || '').trim().toLowerCase();
    const words = currentWords()
      .filter((w) => !q || w.word.toLowerCase().includes(q) || w.meaning.toLowerCase().includes(q))
      .sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));

    const list = $('#words-list');
    if (!words.length) {
      list.innerHTML = '<div class="empty-box">当前词汇本还没有单词，去查词吧～</div>';
      return;
    }
    list.innerHTML = words
      .slice(0, 500)
      .map((w) => {
        const ex = w.examples && w.examples[0];
        const due = window.Scheduler.isDue(w);
        return (
          '<div class="word-item">' +
          '<div class="word-item-head">' +
          '<span class="w">' + escapeHtml(w.word) + '</span>' +
          (w.mastered ? '<span class="tag mastered">已掌握</span>' : '') +
          (due && !w.mastered ? '<span class="tag due">待复习</span>' : '') +
          '<button class="mini-action" data-action="edit" data-id="' + w.id + '">编辑</button>' +
          '<button class="mini-action" data-action="delete" data-id="' + w.id + '">删除</button>' +
          '</div>' +
          '<div class="m">' + escapeHtml(w.meaning) + '</div>' +
          (ex ? '<div class="ex">' + escapeHtml(ex.text) + (ex.translation ? '　→　' + escapeHtml(ex.translation) : '') + '</div>' : '') +
          '</div>'
        );
      })
      .join('') + (words.length > 500 ? '<div class="muted">仅显示前 500 条，可搜索缩小范围</div>' : '');
  }

  function openEdit(id) {
    const w = currentWords().find((x) => x.id === id);
    if (!w) return;
    editingId = id;
    $('#edit-word').value = w.word;
    $('#edit-meaning').value = w.meaning;
    const ex = w.examples && w.examples[0];
    $('#edit-example').value = ex ? ex.text : '';
    $('#edit-example-trans').value = ex ? ex.translation : '';
    $('#edit-modal').classList.remove('hidden');
  }

  function closeEdit() {
    editingId = null;
    $('#edit-modal').classList.add('hidden');
  }

  function saveEdit() {
    const w = currentWords().find((x) => x.id === editingId);
    if (!w) return closeEdit();
    w.word = $('#edit-word').value.trim().toLowerCase() || w.word;
    w.meaning = $('#edit-meaning').value.trim() || w.meaning;
    const text = $('#edit-example').value.trim();
    const trans = $('#edit-example-trans').value.trim();
    if (text) {
      if (!w.examples.length) w.examples.push({ text: text, translation: trans, source: '手动' });
      else {
        w.examples[0].text = text;
        w.examples[0].translation = trans;
      }
    }
    scheduleSave();
    closeEdit();
    renderWords();
  }

  /* ---------------- 导入 / 导出 / 设置 ---------------- */

  function download(name, content, type) {
    const blob = new Blob([content], { type });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function exportData() {
    const book = currentBook();
    const rows = [['word', 'meaning', 'example', 'example_translation', 'mastered']];
    (book.words || []).forEach((w) => {
      const ex = w.examples && w.examples[0];
      rows.push([w.word, w.meaning, ex ? ex.text : '', ex ? ex.translation : '', w.mastered ? '1' : '0']);
    });
    const csv =
      '\uFEFF' +
      rows
        .map((r) => r.map((c) => '"' + String(c == null ? '' : c).replace(/"/g, '""') + '"').join(','))
        .join('\n');
    download(book.name + '.csv', csv, 'text/csv;charset=utf-8');
  }

  function addImported(word, meaning, example, translation) {
    const key = String(word).toLowerCase().trim();
    if (!key || !meaning) return false;
    const words = currentWords();
    const existing = words.find((w) => w.word === key);
    if (existing) return false;
    const ex = example || translation ? { text: example || '', translation: translation || '', source: '导入' } : null;
    const w = {
      id: 'w' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7),
      word: key,
      meaning: String(meaning).trim(),
      phonetic: '',
      examples: ex ? [ex] : [],
      tags: [],
      createdAt: Date.now(),
      mastered: false
    };
    Object.assign(w, window.Scheduler.newWordBase(Date.now() + (data.settings.firstReviewDelayMin || 60) * 60 * 1000));
    words.unshift(w);
    window.Scheduler.updateDailyStats(data.stats, 'add', { added: 1 });
    return true;
  }

  async function handleImportFile(e) {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    e.target.value = '';
    try {
      const text = await file.text();
      let items = [];
      if (file.name.toLowerCase().endsWith('.json')) {
        const parsed = JSON.parse(text);
        items = Array.isArray(parsed) ? parsed : parsed.words || [];
      } else {
        const parseLine = (line) => {
          const out = [];
          let cur = '';
          let inQ = false;
          for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (inQ) {
              if (ch === '"') {
                if (line[i + 1] === '"') { cur += '"'; i++; }
                else inQ = false;
              } else {
                cur += ch;
              }
            } else {
              if (ch === '"') inQ = true;
              else if (ch === ',') { out.push(cur); cur = ''; }
              else cur += ch;
            }
          }
          out.push(cur);
          return out.map((s) => s.trim());
        };
        const lines = text.split(/\r?\n/).filter((l) => l.trim());
        items = lines.map(parseLine).map((cols) => ({
          word: cols[0] || '',
          meaning: cols[1] || '',
          example: cols[2] || '',
          example_translation: cols[3] || ''
        }));
        if (items.length && String(items[0].word).toLowerCase() === 'word') items.shift();
      }
      let added = 0;
      items.forEach((it) => {
        const word = (it.word || it[0] || '').split(';')[0] || '';
        const meaning = (it.meaning || it[1] || '').trim();
        const example = (it.example || it[2] || '').trim();
        const translation = (it.example_translation || it.translation || it[3] || '').trim();
        if (addImported(word, meaning, example, translation)) added += 1;
      });
      if (added > 0) {
        scheduleSave();
        renderWords();
        alert('导入成功，新增 ' + added + ' 个单词（当前词汇本：' + currentBook().name + '）。');
      } else {
        alert('没有导入新单词（可能都已存在或格式不识别）。');
      }
    } catch (err) {
      alert('导入失败：' + err.message);
    }
  }

  function seedDemoWords() {
    const keys = Object.keys(window.Dictionary.OFFLINE_DICT);
    let added = 0;
    keys.slice(0, 30).forEach((key) => {
      if (addImported(key, window.Dictionary.OFFLINE_DICT[key], '', '')) added += 1;
    });
    scheduleSave();
    renderWords();
    alert(added > 0 ? '已导入 ' + added + ' 个示例词到「' + currentBook().name + '」。' : '示例词已在当前词汇本中。');
  }

  /* ---------------- 统计 ---------------- */

  function renderStats() {
    const today = window.Scheduler.computeTodayStats(data.stats);
    const streak = window.Scheduler.computeStreak(data.stats);
    const book = currentBook();
    const words = book.words || [];
    const total = words.length;
    const mastered = words.filter((w) => w.mastered).length;
    const due = words.filter((w) => !w.mastered && window.Scheduler.isDue(w)).length;

    $('#stats-grid').innerHTML =
      statCard(today.added, '今日新增') +
      statCard(today.reviewed, '今日复习') +
      statCard(today.avgRating == null ? '-' : today.avgRating, '平均自评') +
      statCard(streak, '连续打卡') +
      statCard(total, '当前词汇本') +
      statCard(mastered, '已掌握') +
      statCard(due, '待复习') +
      statCard(window.Dictionary.wordCount(), '离线词库');

    $('#stats-detail').innerHTML =
      '<div class="stats-detail-box">' +
      '<p>📖 当前词汇本：<strong>' + escapeHtml(book.name) + '</strong>（' + total + ' 词）</p>' +
      '<p>💡 复习由自适应记忆曲线（SM-2/FSRS 风格）自动安排：自评分越高，下次间隔越长；低分会让单词更快再次出现。</p>' +
      '</div>';
  }

  function statCard(num, label) {
    return '<div class="stat-card"><div class="num">' + escapeHtml(num) + '</div><div class="label">' + escapeHtml(label) + '</div></div>';
  }

  /* ---------------- 面板 / Tab ---------------- */

  function switchTab(tab) {
    currentTab = tab;
    document.querySelectorAll('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    document.querySelectorAll('.tab-page').forEach((p) => p.classList.toggle('active', p.id === 'tab-' + tab));
    if (tab === 'review') refreshReview();
    if (tab === 'words') renderWords();
    if (tab === 'stats') renderStats();
  }

  function setWindowMode(mode) {
    if (window.petAPI && window.petAPI.setWindowMode) {
      window.petAPI.setWindowMode(mode);
    }
  }

  function togglePanel() {
    if ($('#panel').classList.contains('hidden')) openPanel();
    else closePanel();
  }

  async function getWindowPosition() {
    if (window.petAPI && window.petAPI.getWindowPosition) {
      try { return await window.petAPI.getWindowPosition(); } catch (e) { return [0, 0]; }
    }
    return [0, 0];
  }

  function moveWindow(x, y) {
    if (window.petAPI && window.petAPI.setWindowPosition) {
      window.petAPI.setWindowPosition(x, y);
    }
  }

  function beginWindowDrag() {
    if (window.petAPI && window.petAPI.beginWindowDrag) {
      window.petAPI.beginWindowDrag();
    }
  }

  function endWindowDrag() {
    if (window.petAPI && window.petAPI.endWindowDrag) {
      window.petAPI.endWindowDrag();
    }
  }

  let petDrag = null;
  let petDragMoved = false;

  function openPanel() {
    $('#panel').classList.remove('hidden');
    setWindowMode('panel');
    setPet('summon', '我在呢！');
    setTimeout(() => {
      if (currentTab === 'query') $('#query-input').focus();
    }, 120);
  }

  function closePanel() {
    $('#panel').classList.add('hidden');
    setWindowMode('pet');
    setPet('idle');
  }

  /* ---------------- 初始化 ---------------- */

  function bindEvents() {
    document.querySelectorAll('.tab').forEach((btn) => {
      btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });

    // 桌宠：单击切换面板，拖动移动窗口（自定义拖拽）
    $('#pet-bar').addEventListener('mousedown', async (e) => {
      if (e.button !== 0) return;
      const [wx, wy] = await getWindowPosition();
      petDrag = { sx: e.screenX, sy: e.screenY, wx, wy };
      petDragMoved = false;
      // 记住拖动开始时的窗口尺寸，防止 Windows 透明窗在移动时尺寸漂移（面板被拉伸）
      beginWindowDrag();
      e.preventDefault();
    });

    document.addEventListener('mousemove', (e) => {
      if (!petDrag) return;
      if (!(e.buttons & 1)) {
        petDrag = null;
        return;
      }
      const dx = e.screenX - petDrag.sx;
      const dy = e.screenY - petDrag.sy;
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) petDragMoved = true;
      if (petDragMoved) moveWindow(petDrag.wx + dx, petDrag.wy + dy);
    });

    document.addEventListener('mouseup', () => {
      if (!petDrag) return;
      const moved = petDragMoved;
      petDrag = null;
      endWindowDrag();
      if (!moved) togglePanel();
    });

    // 内容过多时：上下方向键浏览面板内容
    document.addEventListener('keydown', (e) => {
      if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
      const tag = e.target && e.target.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if ($('#panel').classList.contains('hidden')) return;
      const content = $('.content');
      if (!content) return;
      content.scrollTop += e.key === 'ArrowDown' ? 60 : -60;
      e.preventDefault();
    });

    $('#query-btn').addEventListener('click', handleQuery);
    $('#query-input').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handleQuery();
    });

    $('#review-submit').addEventListener('click', submitReviewAnswer);
    $('#review-answer').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') submitReviewAnswer();
    });
    $('#review-skip').addEventListener('click', skipReview);
    $('#review-known').addEventListener('click', markKnown);

    $('#book-select').addEventListener('change', (e) => {
      data.settings.activeBookId = e.target.value;
      scheduleSave();
      renderAll();
      switchTab('words');
    });
    $('#btn-new-book').addEventListener('click', openBookModal);
    $('#btn-delete-book').addEventListener('click', deleteBook);
    $('#book-create').addEventListener('click', createBook);
    $('#book-cancel').addEventListener('click', closeBookModal);
    $('#book-modal').addEventListener('click', (e) => {
      if (e.target === e.currentTarget) closeBookModal();
    });
    $('#book-name').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') createBook();
    });

    $('#words-search').addEventListener('input', renderWords);
    $('#words-list').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-action]');
      if (!btn) return;
      const id = btn.dataset.id;
      const action = btn.dataset.action;
      if (action === 'edit') openEdit(id);
      if (action === 'delete') {
        if (confirm('确定删除这个单词？（当前词汇本）')) {
          const book = currentBook();
          book.words = book.words.filter((w) => w.id !== id);
          scheduleSave();
          renderWords();
        }
      }
    });

    $('#btn-import').addEventListener('click', () => $('#file-import').click());
    $('#file-import').addEventListener('change', handleImportFile);
    $('#btn-export').addEventListener('click', exportData);

    $('#edit-save').addEventListener('click', saveEdit);
    $('#edit-cancel').addEventListener('click', closeEdit);
    $('#edit-modal').addEventListener('click', (e) => {
      if (e.target === e.currentTarget) closeEdit();
    });

    $('#setting-quota').addEventListener('change', (e) => {
      data.settings.dailyQuota = Math.max(1, Math.min(200, Number(e.target.value) || 20));
      scheduleSave();
    });
    $('#setting-show-example').addEventListener('change', (e) => {
      data.settings.showExampleBeforeAnswer = e.target.checked;
      scheduleSave();
    });
    $('#setting-auto-launch').addEventListener('change', async (e) => {
      const result = await setAutoLaunch(e.target.checked);
      e.target.checked = result;
      if (!e.target.checked) alert('设置开机自启动失败（可能当前环境不支持）');
    });

    $('#btn-reset').addEventListener('click', () => {
      if (confirm('清空当前词汇本「' + currentBook().name + '」的全部单词？（不可恢复）')) {
        currentBook().words = [];
        scheduleSave();
        renderWords();
        renderStats();
        renderBookSelect();
      }
    });
    $('#btn-seed').addEventListener('click', seedDemoWords);

    if (window.petAPI && window.petAPI.onShortcut) {
      window.petAPI.onShortcut(() => openPanel());
    }
    if (window.petAPI && window.petAPI.onShortcutHide) {
      window.petAPI.onShortcutHide(() => closePanel());
    }
    if (window.petAPI && window.petAPI.onPetShown) {
      window.petAPI.onPetShown(() => {
        if ($('#panel').classList.contains('hidden')) setPet('summon');
      });
    }

    setInterval(() => {
      if ($('#panel').classList.contains('hidden')) {
        setPet('idle');
      }
    }, 25000);
  }

  function renderAll() {
    $('#setting-quota').value = data.settings.dailyQuota || 20;
    $('#setting-show-example').checked = !!data.settings.showExampleBeforeAnswer;
    $('#setting-dict-count').textContent = window.Dictionary.wordCount() + ' 词';
    renderBookSelect();
    renderWords();
    renderStats();
    refreshReview();
  }

  async function init() {
    data = await loadData();
    if (!data || typeof data !== 'object') data = cloneDefaults();
    if (!Array.isArray(data.books)) data.books = [];
    if (!data.stats) data.stats = { days: {} };
    if (!data.settings) data.settings = Object.assign({}, DEFAULTS.settings);
    migrateAndEnsureBooks();
    bindEvents();
    renderAll();
    setWindowMode('pet');

    const auto = await getAutoLaunch();
    $('#setting-auto-launch').checked = auto;

    setPet('summon', '🔑 快捷键\nAlt+W 呼出\nAlt+E 隐藏\nAlt+P 显/隐桌宠', 8000);

    // 仅用于开发/自动测试
    window.__petDebug = {
      getData: () => data,
      setDue: (word) => {
        const w = currentWords().find((x) => x.word.toLowerCase() === String(word).toLowerCase());
        if (w) w.nextReview = Date.now() - 1000;
        refreshReview();
      },
      currentBook: () => currentBook(),
      createBook: createBook,
      openPanel: openPanel,
      closePanel: closePanel
    };
  }

  init();
})();
