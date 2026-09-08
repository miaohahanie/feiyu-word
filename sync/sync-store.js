/**
 * 手机同步的独立配置存储（word-pet-sync.json）。
 * 与 word-pet-data.json 分离，避免渲染进程保存数据时把设备/配对信息覆盖掉。
 *
 * 写入策略：临时文件 + rename 原子替换，保留 .bak；
 * 主文件损坏时自动尝试从 .bak 恢复，损坏文件隔离保存。
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DEFAULT_CONFIG = {
  server: {
    enabled: false,
    port: 8787,
    pairingCode: '',
    codeExpiresAt: 0,
    selectedIp: ''
  },
  devices: [],
  tombstones: []
};

// 墓碑保留时长：超过后裁剪，防止无限增长。
// 手机离线超过该时长可能无法感知更早的删除，属于可接受取舍。
const TOMBSTONE_TTL = 90 * 24 * 60 * 60 * 1000;
const MAX_PAIR_FAILS = 5;

function createSyncStore(filePath) {
  let pairFails = 0;
  let config = loadConfig();

  function loadConfig() {
    const candidates = [filePath, filePath + '.bak'];
    for (const p of candidates) {
      try {
        if (!fs.existsSync(p)) continue;
        const parsed = JSON.parse(fs.readFileSync(p, 'utf8'));
        if (parsed && typeof parsed === 'object') {
          if (p !== filePath) {
            try { fs.copyFileSync(p, filePath); } catch (e) { /* 恢复失败则用内存默认值 */ }
          }
          const cfg = Object.assign(JSON.parse(JSON.stringify(DEFAULT_CONFIG)), parsed);
          if (!Array.isArray(cfg.devices)) cfg.devices = [];
          if (!Array.isArray(cfg.tombstones)) cfg.tombstones = [];
          if (!cfg.server) cfg.server = JSON.parse(JSON.stringify(DEFAULT_CONFIG.server));
          return cfg;
        }
      } catch (e) {
        if (p === filePath) {
          try { fs.renameSync(filePath, filePath + '.corrupt-' + Date.now()); } catch (e2) { /* ignore */ }
        }
      }
    }
    return JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  }

  function save() {
    try {
      fs.mkdirSync(path.dirname(filePath), { recursive: true });
      const tmp = filePath + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify(config, null, 2), 'utf8');
      try {
        if (fs.existsSync(filePath)) fs.copyFileSync(filePath, filePath + '.bak');
      } catch (e) { /* 备份失败不阻塞写入 */ }
      fs.renameSync(tmp, filePath);
      return true;
    } catch (e) {
      return false;
    }
  }

  function hashToken(token) {
    return crypto.createHash('sha256').update(String(token || '')).digest('hex');
  }

  function makeToken() {
    return crypto.randomBytes(32).toString('hex');
  }

  function genCode() {
    config.server.pairingCode = String(crypto.randomInt(100000, 1000000));
    config.server.codeExpiresAt = Date.now() + 10 * 60 * 1000; // 10 分钟
    pairFails = 0;
    save();
    return config.server.pairingCode;
  }

  function ensureCode() {
    if (!config.server.pairingCode || !config.server.codeExpiresAt || config.server.codeExpiresAt < Date.now()) {
      genCode();
    }
    return config.server.pairingCode;
  }

  function pair(code, name) {
    const c = String(code || '').trim();
    const valid =
      c && c === config.server.pairingCode && config.server.codeExpiresAt >= Date.now();
    if (!valid) {
      pairFails += 1;
      if (pairFails >= MAX_PAIR_FAILS) {
        // 连续失败太多次：作废当前码并换新码，桌面端状态刷新后会展示新码
        genCode();
      }
      return null;
    }
    pairFails = 0;
    const deviceId = crypto.randomUUID();
    const token = makeToken();
    const cleanName =
      String(name || '').trim().replace(/[\r\n\t]/g, '').slice(0, 40) || 'Android 手机';
    config.devices.push({
      deviceId,
      name: cleanName,
      tokenHash: hashToken(token),
      pairedAt: Date.now(),
      lastSyncAt: 0
    });
    // 配对码一次性：成功即作废，防止旧码重放
    config.server.pairingCode = '';
    config.server.codeExpiresAt = 0;
    save();
    return { deviceId, token };
  }

  function findDevice(deviceId, token) {
    const d = config.devices.find((x) => x.deviceId === deviceId);
    if (!d) return null;
    if (d.tokenHash !== hashToken(token)) return null;
    return d;
  }

  function listDevices() {
    return config.devices.map((d) => ({
      deviceId: d.deviceId,
      name: d.name || 'Android 手机',
      pairedAt: d.pairedAt || 0,
      lastSyncAt: d.lastSyncAt || 0
    }));
  }

  function removeDevice(deviceId) {
    config.devices = config.devices.filter((d) => d.deviceId !== deviceId);
    save();
  }

  function touchDevice(deviceId) {
    const d = config.devices.find((x) => x.deviceId === deviceId);
    if (d) {
      d.lastSyncAt = Date.now();
      save();
    }
  }

  function pruneTombstones() {
    const cutoff = Date.now() - TOMBSTONE_TTL;
    if (config.tombstones.some((t) => (t.deletedAt || 0) <= cutoff)) {
      config.tombstones = config.tombstones.filter((t) => (t.deletedAt || 0) > cutoff);
      return true;
    }
    return false;
  }

  function addTombstones(bookId, words) {
    const keys = (Array.isArray(words) ? words : [words])
      .map((w) => String(w || '').toLowerCase().trim())
      .filter((k) => k);
    if (!bookId || !keys.length) return false;
    const existing = new Set(
      config.tombstones.filter((t) => t.bookId === bookId).map((t) => t.word)
    );
    const now = Date.now();
    let changed = false;
    for (const key of keys) {
      if (existing.has(key)) continue;
      config.tombstones.push({ bookId, word: key, deletedAt: now });
      existing.add(key);
      changed = true;
    }
    if (changed || pruneTombstones()) save();
    return changed;
  }

  function addTombstone(bookId, word) {
    return addTombstones(bookId, [word]);
  }

  // 重新添加单词时清除对应墓碑，否则手机端会把新词误删（拉取后按墓碑过滤）
  function removeTombstone(bookId, word) {
    const key = String(word || '').toLowerCase().trim();
    if (!bookId || !key) return;
    const before = config.tombstones.length;
    config.tombstones = config.tombstones.filter(
      (t) => !(t.bookId === bookId && t.word === key)
    );
    if (config.tombstones.length !== before) save();
  }

  function getTombstones(bookId, since) {
    const s = Number(since) || 0;
    return config.tombstones
      .filter((t) => (!bookId || t.bookId === bookId) && t.deletedAt > s)
      .map((t) => ({ word: t.word, deletedAt: t.deletedAt }));
  }

  function getServerConfig() {
    ensureCode();
    return JSON.parse(JSON.stringify(config.server));
  }

  function setServerEnabled(enabled) {
    config.server.enabled = !!enabled;
    save();
  }

  function setPort(port) {
    const p = Math.max(1024, Math.min(65535, Math.round(Number(port) || 8787)));
    config.server.port = p;
    save();
    return p;
  }

  function setSelectedIp(ip) {
    config.server.selectedIp = String(ip || '').trim();
    save();
    return config.server.selectedIp;
  }

  return {
    genCode,
    ensureCode,
    pair,
    findDevice,
    listDevices,
    removeDevice,
    touchDevice,
    addTombstone,
    addTombstones,
    removeTombstone,
    getTombstones,
    getServerConfig,
    setServerEnabled,
    setPort,
    setSelectedIp,
    getFilePath: () => filePath
  };
}

module.exports = { createSyncStore };
