/**
 * 手机同步的独立配置存储（word-pet-sync.json）。
 * 与 word-pet-data.json 分离，避免渲染进程保存数据时把设备/配对信息覆盖掉。
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

function createSyncStore(filePath) {
  let config = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      config = Object.assign(JSON.parse(JSON.stringify(DEFAULT_CONFIG)), parsed);
      if (!config.devices) config.devices = [];
      if (!config.tombstones) config.tombstones = [];
      if (!config.server) config.server = JSON.parse(JSON.stringify(DEFAULT_CONFIG.server));
    }
  } catch (e) {
    /* 首次运行/文件损坏时用默认值 */
  }

  function save() {
    try {
      fs.mkdirSync(path.dirname(filePath), { recursive: true });
      fs.writeFileSync(filePath, JSON.stringify(config, null, 2), 'utf8');
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
    const code = String(Math.floor(100000 + Math.random() * 900000));
    config.server.pairingCode = code;
    config.server.codeExpiresAt = Date.now() + 10 * 60 * 1000; // 10 分钟
    save();
    return code;
  }

  function ensureCode() {
    if (!config.server.pairingCode || !config.server.codeExpiresAt || config.server.codeExpiresAt < Date.now()) {
      genCode();
    }
    return config.server.pairingCode;
  }

  function pair(code) {
    const c = String(code || '').trim();
    if (!c || c !== config.server.pairingCode || config.server.codeExpiresAt < Date.now()) return null;
    const deviceId = crypto.randomUUID();
    const token = makeToken();
    config.devices.push({
      deviceId,
      name: 'Android 手机',
      tokenHash: hashToken(token),
      pairedAt: Date.now(),
      lastSyncAt: 0
    });
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

  function addTombstone(bookId, word) {
    const key = String(word || '').toLowerCase().trim();
    if (!bookId || !key) return;
    if (!config.tombstones.some((t) => t.bookId === bookId && t.word === key)) {
      config.tombstones.push({ bookId, word: key, deletedAt: Date.now() });
      save();
    }
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
    getTombstones,
    getServerConfig,
    setServerEnabled,
    setPort,
    setSelectedIp,
    getFilePath: () => filePath
  };
}

module.exports = { createSyncStore };
