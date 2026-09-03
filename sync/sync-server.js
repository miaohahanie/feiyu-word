/**
 * 电脑端局域网同步服务（M1）。
 * 提供：配对、词本列表、增量拉取、复习事件上传、设备管理。
 * 依赖：sync/sync-store.js、sync/scheduler.js、sync/qr.js、qrcode。
 */
'use strict';

const http = require('http');
const os = require('os');
const crypto = require('crypto');
const { rateWord } = require('./scheduler');
const { buildPairUrl, makePairQrDataUrl } = require('./qr');

const VPN_NAME_PATTERNS = /radmin|vpn|tun|tap|virtual|wireguard|zerotier|tailscale|hamachi|loopback|wsl/i;
const CGNAT_RE = /^(100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)/;
const LINK_LOCAL_RE = /^169\.254\./;

function isPrivateLan(ip) {
  return /^192\.168\./.test(ip) || /^10\./.test(ip) || /^172\.(1[6-9]|2\d|3[01])\./.test(ip);
}

function scoreNetwork(name, ip) {
  let score = 0;
  if (/radmin/i.test(name)) score -= 120;
  if (VPN_NAME_PATTERNS.test(name)) score -= 80;
  if (/wlan|wi-?fi|ethernet|以太|无线|本地连接/i.test(name)) score += 10;
  if (/^192\.168\./.test(ip)) score += 120;
  else if (/^10\./.test(ip)) score += 110;
  else if (/^172\.(1[6-9]|2\d|3[01])\./.test(ip)) score += 100;
  if (isPrivateLan(ip)) score += 100;
  if (CGNAT_RE.test(ip)) score -= 80;
  if (LINK_LOCAL_RE.test(ip)) score -= 100;
  return score;
}

function listNetworks() {
  const out = [];
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === 'IPv4' && !net.internal) {
        out.push({
          name,
          address: net.address,
          netmask: net.netmask,
          cidr: net.cidr || '',
          score: scoreNetwork(name, net.address)
        });
      }
    }
  }
  out.sort((a, b) => b.score - a.score || a.address.localeCompare(b.address));
  return out;
}

function getLanIPs() {
  return listNetworks().map((n) => n.address);
}

function wordToSync(w) {
  return {
    word: w.word,
    meaning: w.meaning || '',
    phonetic: w.phonetic || '',
    examples: Array.isArray(w.examples) ? w.examples : [],
    reps: Number(w.reps) || 0,
    ease: Number(w.ease) > 0 ? Number(w.ease) : 2.5,
    interval: Number(w.interval) || 0,
    lapses: Number(w.lapses) || 0,
    lastRating: typeof w.lastRating === 'number' ? w.lastRating : null,
    nextReview: Number(w.nextReview) || 0,
    mastered: !!w.mastered,
    updatedAt: Number(w.updatedAt) || 0,
    deleted: !!w.deleted
  };
}

function applyEvents(data, bookId, events) {
  const book = data && Array.isArray(data.books) ? data.books.find((b) => b.id === bookId) : null;
  if (!book || !Array.isArray(book.words)) {
    return { accepted: 0, ignored: Array.isArray(events) ? events.length : 0, changedWords: [] };
  }
  let accepted = 0;
  let ignored = 0;
  const changedWords = [];
  const appliedIds = [];

  for (const ev of Array.isArray(events) ? events : []) {
    if (!ev || !ev.eventId || !ev.word || typeof ev.rating !== 'number') {
      ignored += 1;
      continue;
    }
    const key = String(ev.word).toLowerCase().trim();
    const w = book.words.find((x) => String(x.word || '').toLowerCase() === key);
    if (!w) {
      ignored += 1;
      continue;
    }
    if ((w.history || []).some((h) => h && h.id === ev.eventId) || appliedIds.includes(ev.eventId)) {
      ignored += 1;
      continue;
    }
    const now = Number(ev.createdAt) || Date.now();
    appliedIds.push(ev.eventId);
    rateWord(w, ev.rating, now, ev.eventId);
    w.updatedAt = Math.max(Number(w.updatedAt) || 0, now);

    // 更新每日统计（与渲染进程 updateDailyStats 一致）
    if (!data.stats) data.stats = { days: {} };
    if (!data.stats.days) data.stats.days = {};
    const d = new Date(now);
    const dayKey = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    if (!data.stats.days[dayKey]) data.stats.days[dayKey] = { added: 0, reviewed: 0, ratings: [] };
    data.stats.days[dayKey].reviewed += 1;
    data.stats.days[dayKey].ratings.push(Number(ev.rating));

    accepted += 1;
    changedWords.push(wordToSync(w));
  }

  return { accepted, ignored, changedWords };
}

function createSyncServer({ store, getData, saveData, lookupWord, notifyDataChanged }) {
  let server = null;
  let activePort = 0;
  let lastError = '';

  function parseBody(req) {
    return new Promise((resolve, reject) => {
      let body = '';
      req.on('data', (chunk) => {
        body += chunk;
        if (body.length > 5 * 1024 * 1024) {
          reject(new Error('请求体过大'));
          req.destroy();
        }
      });
      req.on('end', () => {
        if (!body) return resolve({});
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          reject(new Error('无效 JSON'));
        }
      });
      req.on('error', reject);
    });
  }

  function sendJson(res, status, obj) {
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Device-Id',
      'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS'
    });
    res.end(JSON.stringify(obj));
  }

  function auth(req) {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    const deviceId = req.headers['device-id'] || '';
    if (!token || !deviceId) return null;
    return store.findDevice(deviceId, token);
  }

  function bookList() {
    const data = getData() || { books: [] };
    return (data.books || []).map((b) => ({
      id: b.id,
      name: b.name || '',
      description: b.description || '',
      builtin: !!b.builtin,
      count: Array.isArray(b.words) ? b.words.length : 0
    }));
  }

  async function handle(req, res) {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    const pathname = url.pathname;

    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, Device-Id',
        'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS'
      });
      return res.end();
    }

    try {
      // 健康检查（无需鉴权）
      if (pathname === '/api/health' && req.method === 'GET') {
        return sendJson(res, 200, { ok: true, appVersion: '0.3.2+M1', serverTime: Date.now() });
      }

      // 配对
      if (pathname === '/api/pair' && req.method === 'POST') {
        const body = await parseBody(req);
        const paired = store.pair(body && body.code);
        if (!paired) {
          return sendJson(res, 401, { error: '配对码无效或已过期' });
        }
        return sendJson(res, 200, {
          deviceId: paired.deviceId,
          token: paired.token,
          serverTime: Date.now(),
          books: bookList()
        });
      }

      // 以下接口均需鉴权
      const device = auth(req);
      if (!device) {
        return sendJson(res, 401, { error: '未授权设备' });
      }

      if (pathname === '/api/books' && req.method === 'GET') {
        store.touchDevice(device.deviceId);
        return sendJson(res, 200, { serverTime: Date.now(), books: bookList() });
      }

      if (pathname === '/api/sync' && req.method === 'GET') {
        const bookId = url.searchParams.get('book') || '';
        const since = Number(url.searchParams.get('since') || 0) || 0;
        const data = getData() || { books: [] };
        const book = data.books.find((b) => b.id === bookId);
        if (!book) return sendJson(res, 404, { error: '词本不存在' });
        const words = (book.words || [])
          .map(wordToSync)
          .filter((w) => since <= 0 || w.updatedAt > since || w.deleted);
        const tombstones = store.getTombstones(bookId, since);
        store.touchDevice(device.deviceId);
        return sendJson(res, 200, {
          serverTime: Date.now(),
          book: { id: book.id, name: book.name || '' },
          words,
          tombstones
        });
      }

      if (pathname === '/api/sync' && req.method === 'POST') {
        const body = await parseBody(req);
        const data = getData() || { books: [], stats: { days: {} } };
        const result = applyEvents(data, body.bookId || '', body.events || []);
        if (result.accepted > 0) {
          saveData(data);
          store.touchDevice(device.deviceId);
          if (typeof notifyDataChanged === 'function') notifyDataChanged();
        }
        return sendJson(res, 200, {
          serverTime: Date.now(),
          accepted: result.accepted,
          ignored: result.ignored,
          conflicts: [],
          changedWords: result.changedWords
        });
      }

      // 手机端在线查词
      if (pathname === '/api/lookup' && req.method === 'POST') {
        const body = await parseBody(req);
        const word = String(body.word || '').trim();
        if (!word) return sendJson(res, 400, { error: '缺少单词' });
        const result = typeof lookupWord === 'function' ? await lookupWord(word) : null;
        if (!result || !result.meaning) return sendJson(res, 404, { error: '未找到释义' });
        return sendJson(res, 200, {
          ok: true,
          word: word.toLowerCase(),
          meaning: result.meaning,
          phonetic: result.phonetic || '',
          source: result.source || ''
        });
      }

      // 手机端添加单词（可带释义，缺释义时在线查）
      if (pathname === '/api/word' && req.method === 'POST') {
        const body = await parseBody(req);
        const bookId = String(body.bookId || '').trim();
        const key = String(body.word || '').trim().toLowerCase();
        if (!bookId || !key || !/^[a-zA-Z][a-zA-Z\-' ]*$/.test(key)) {
          return sendJson(res, 400, { error: '词本或单词格式不正确' });
        }
        const data = getData() || { books: [], stats: { days: {} }, settings: {} };
        const book = data.books.find((b) => b.id === bookId);
        if (!book) return sendJson(res, 404, { error: '词本不存在' });
        if (!Array.isArray(book.words)) book.words = [];

        const existing = book.words.find((w) => String(w.word || '').toLowerCase() === key);
        let meaning = String(body.meaning || '').trim();
        let phonetic = String(body.phonetic || '').trim();
        if (!meaning && typeof lookupWord === 'function') {
          const r = await lookupWord(key);
          if (r && r.meaning) {
            meaning = r.meaning;
            if (!phonetic) phonetic = r.phonetic || '';
          }
        }
        if (!meaning) {
          return sendJson(res, 400, { error: '缺少释义，且在线查词失败，请手动补充中文释义' });
        }

        let w = existing;
        if (w) {
          w.meaning = meaning;
          if (phonetic) w.phonetic = phonetic;
          w.updatedAt = Date.now();
        } else {
          w = {
            id: 'w' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7),
            word: key,
            meaning,
            phonetic,
            examples: [],
            tags: [],
            createdAt: Date.now(),
            updatedAt: Date.now(),
            mastered: false,
            reps: 0,
            ease: 2.5,
            interval: 0,
            lapses: 0,
            history: [],
            lastRating: null,
            nextReview: Date.now() + ((data.settings && data.settings.firstReviewDelayMin) || 60) * 60 * 1000
          };
          book.words.unshift(w);
        }
        saveData(data);
        store.touchDevice(device.deviceId);
        if (typeof notifyDataChanged === 'function') notifyDataChanged();
        return sendJson(res, 200, { ok: true, word: wordToSync(w) });
      }

      // 删除配对设备（同一设备 token 或任意已授权设备均可删除）
      const m = pathname.match(/^\/api\/device\/([\w-]+)$/);
      if (m && req.method === 'DELETE') {
        store.removeDevice(m[1]);
        return sendJson(res, 200, { ok: true });
      }

      return sendJson(res, 404, { error: '接口不存在' });
    } catch (e) {
      return sendJson(res, 500, { error: String((e && e.message) || e) });
    }
  }

  async function start(portOverride) {
    if (server) return getStatus();
    const cfg = store.getServerConfig();
    const port = store.setPort(portOverride || cfg.port);
    await new Promise((resolve, reject) => {
      const srv = http.createServer(handle);
      srv.on('error', (e) => {
        lastError = String(e && e.message || e);
        server = null;
        activePort = 0;
        reject(e);
      });
      srv.listen(port, '0.0.0.0', () => {
        server = srv;
        activePort = srv.address().port;
        store.setServerEnabled(true);
        store.setPort(activePort);
        lastError = '';
        resolve();
      });
    });
    return getStatus();
  }

  function stop() {
    return new Promise((resolve) => {
      if (!server) {
        store.setServerEnabled(false);
        return resolve(getStatus());
      }
      const srv = server;
      server = null;
      activePort = 0;
      store.setServerEnabled(false);
      srv.close(() => resolve(getStatus()));
    });
  }

  async function getStatus() {
    const cfg = store.getServerConfig();
    const enabled = !!server;
    const networks = listNetworks();
    let selected = networks.find((n) => n.address === cfg.selectedIp) || null;
    if (!selected && networks.length) selected = networks[0];
    const ip = selected ? selected.address : '';
    let qr = null;
    if (enabled && selected) {
      try {
        qr = await makePairQrDataUrl(selected.address, activePort, cfg.pairingCode);
      } catch (e) {
        /* QR 失败不影响服务 */
      }
    }
    return {
      enabled,
      port: activePort || cfg.port,
      ip,
      ips: networks.map((n) => n.address),
      networks: networks.map((n) => ({ name: n.name, address: n.address })),
      selectedIp: ip,
      pairingCode: cfg.pairingCode,
      codeExpiresAt: cfg.codeExpiresAt,
      qr,
      devices: store.listDevices(),
      error: lastError
    };
  }

  async function setPreferredIp(ip) {
    store.setSelectedIp(ip);
    return getStatus();
  }

  return { start, stop, getStatus, setPreferredIp };
}

module.exports = { createSyncServer, getLanIPs, listNetworks };
