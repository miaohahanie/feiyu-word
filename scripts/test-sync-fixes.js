/* 临时功能测试：验证本轮修复的核心行为（不走 Electron）。 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

const { createSyncStore } = require('../sync/sync-store');
const { createSyncServer } = require('../sync/sync-server');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wordpet-test-'));
const storePath = path.join(tmp, 'word-pet-sync.json');
const dataPath = path.join(tmp, 'word-pet-data.json');

/* ---------- 1) store：配对限速 + 一次性码 ---------- */
{
  const store = createSyncStore(storePath);
  const code = store.genCode();
  assert(/^\d{6}$/.test(code), 'code 6 位');
  for (let i = 0; i < 5; i++) {
    assert.strictEqual(store.pair('000000'), null, '错误码配对失败 ' + i);
  }
  // 连续失败 5 次 → 旧码作废换新码，旧码永远配不上
  assert.notStrictEqual(store.ensureCode(), code, '锁定后换了新码');
  assert.strictEqual(store.pair(code, 'x'), null, '旧码已作废');

  const code2 = store.ensureCode();
  const ok = store.pair(code2, '我的手机');
  assert.ok(ok && ok.token, '正确码配对成功');
  assert.strictEqual(store.pair(code2, '重放'), null, '配对码一次性');
  assert.strictEqual(store.listDevices()[0].name, '我的手机', '设备名来自请求');
}

/* ---------- 2) store：墓碑批量/清除/裁剪 + 损坏恢复 ---------- */
{
  const store = createSyncStore(storePath);
  store.addTombstones('b1', ['Cat', 'Dog ', 'cat']); // 去重 + 归一化
  assert.strictEqual(store.getTombstones('b1', 0).length, 2, '批量墓碑去重');
  store.removeTombstone('b1', 'CAT');
  assert.strictEqual(store.getTombstones('b1', 0).length, 1, 'removeTombstone 大小写不敏感');

  // 损坏恢复：写坏主文件，重建 store 应从 .bak 恢复（.bak 是上一版，最多丢一次增量）
  store.addTombstone('b2', 'island');
  store.addTombstone('b3', 'temp'); // 再保存一次，让 island 进入 .bak
  const raw = fs.readFileSync(storePath, 'utf8');
  assert.ok(raw.includes('island'), '墓碑已落盘');
  fs.writeFileSync(storePath, '{broken json', 'utf8');
  const store2 = createSyncStore(storePath);
  assert.ok(
    store2.getTombstones('b2', 0).some((t) => t.word === 'island'),
    '主文件损坏后从 .bak 恢复'
  );
  assert.ok(fs.readdirSync(tmp).some((f) => f.includes('.corrupt-')), '损坏文件被隔离');
}

/* ---------- 3) server：HTTP 全链路 ---------- */
const data = {
  books: [
    {
      id: 'book-1',
      name: '测试本',
      words: [
        {
          id: 'w1', word: 'apple', meaning: '苹果', phonetic: '', examples: [],
          reps: 1, ease: 2.5, interval: 0, lapses: 0, history: [
            { id: 'evt-0', date: '2026-01-01T00:00:00.000Z', rating: 8 }
          ],
          lastRating: 8, nextReview: 0, mastered: false, updatedAt: 1
        }
      ]
    }
  ],
  stats: { days: {} },
  settings: {}
};

const serverBox = createSyncServer({
  store: (() => { const s = createSyncStore(path.join(tmp, 'srv-sync.json')); s.genCode(); return s; })(),
  getData: () => data,
  saveData: (d) => { fs.writeFileSync(dataPath, JSON.stringify(d)); },
  withDataLock: (fn) => fn(),
  appVersion: '9.9.9-test',
  lookupWord: async () => ({ meaning: '在线释义', phonetic: '', source: 'test' }),
  notifyDataChanged: () => {}
});

function req(method, p, body, headers) {
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body), 'utf8') : null;
    const r = http.request(
      { host: '127.0.0.1', port: serverBox.port, method, path: p,
        headers: Object.assign(
          payload ? { 'Content-Type': 'application/json' } : {},
          headers || {}
        ) },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve({ status: res.statusCode, json: JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}') }));
      }
    );
    r.on('error', reject);
    if (payload) r.end(payload); else r.end();
  });
}

(async () => {
  const status = await serverBox.start(0);
  serverBox.port = status.port;

  // Host 校验：伪造域名被拒
  {
    const res = await new Promise((resolve, reject) => {
      const r = http.request({ host: '127.0.0.1', port: status.port, method: 'GET', path: '/api/health', headers: { Host: 'evil.example.com' } }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve({ status: res.statusCode }));
      });
      r.on('error', reject); r.end();
    });
    assert.strictEqual(res.status, 403, 'DNS rebinding Host 被拒');
  }

  // health 带真实版本号
  const health = await req('GET', '/api/health');
  assert.strictEqual(health.json.appVersion, '9.9.9-test', '版本号来自主程序');
  assert.strictEqual(health.status, 200);

  // 无 CORS 头
  assert.strictEqual(health.res, undefined);
  const rawHealth = await new Promise((resolve, reject) => {
    const r = http.request({ host: '127.0.0.1', port: status.port, method: 'GET', path: '/api/health' }, (res) => {
      resolve(res.headers);
    });
    r.on('error', reject); r.end();
  });
  assert.ok(!rawHealth['access-control-allow-origin'], '不再返回 CORS 头');

  // 配对拿凭证
  const code = status.pairingCode;
  const pairRes = await req('POST', '/api/pair', { code, name: '测试手机' });
  assert.strictEqual(pairRes.status, 200, '配对成功');
  const auth = { Authorization: 'Bearer ' + pairRes.json.token, 'Device-Id': pairRes.json.deviceId };
  assert.strictEqual((await req('POST', '/api/pair', { code })).status, 401, '配对码一次性');

  // GET /api/sync：wordToSync 带 history
  const sync1 = await req('GET', '/api/sync?book=book-1&since=0', null, auth);
  assert.strictEqual(sync1.status, 200);
  assert.ok(Array.isArray(sync1.json.words[0].history) && sync1.json.words[0].history[0].id === 'evt-0', 'history 随词下发');
  assert.strictEqual((await req('GET', '/api/sync?book=book-1&since=abc', null, auth)).status, 400, 'since 非法被拒');

  // POST 复习事件 → 幂等
  const push = await req('POST', '/api/sync', { bookId: 'book-1', events: [
    { eventId: 'evt-1', word: 'apple', rating: 8, createdAt: Date.now() }
  ] }, auth);
  assert.strictEqual(push.json.accepted, 1, '事件被接受');
  const pushAgain = await req('POST', '/api/sync', { bookId: 'book-1', events: [
    { eventId: 'evt-1', word: 'apple', rating: 8, createdAt: Date.now() }
  ] }, auth);
  assert.strictEqual(pushAgain.json.accepted, 0, '同 eventId 幂等去重');

  // 中文释义跨 chunk：用小 socket 逐字节写，验证 UTF-8 不截断
  {
    const big = { bookId: 'book-1', word: 'zerotest', meaning: '一个很长很长的中文释义'.repeat(100) };
    const payload = Buffer.from(JSON.stringify(big), 'utf8');
    const status2 = await new Promise((resolve, reject) => {
      const r = http.request({ host: '127.0.0.1', port: status.port, method: 'POST', path: '/api/word',
        headers: Object.assign({ 'Content-Type': 'application/json' }, auth) }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))));
      });
      r.on('error', reject);
      // 每 7 字节一块（非 UTF-8 边界对齐），模拟最恶劣的分块
      let i = 0;
      const timer = setInterval(() => {
        if (i >= payload.length) { clearInterval(timer); r.end(); return; }
        r.write(payload.subarray(i, Math.min(i + 7, payload.length)));
        i += 7;
      }, 1);
    });
    assert.ok(status2.ok, '跨 chunk 中文入库成功');
    const pulled = await req('GET', '/api/sync?book=book-1&since=0', null, auth);
    const w = pulled.json.words.find((x) => x.word === 'zerotest');
    assert.strictEqual(w.meaning, big.meaning, '中文释义无损');

    // 删除 → 墓碑；重新添加 → 墓碑被清除（修复点 1）
    await req('DELETE', '/api/word?book=book-1&word=zerotest', null, auth);
    const afterDel = await req('GET', '/api/sync?book=book-1&since=0', null, auth);
    assert.ok(!afterDel.json.words.some((x) => x.word === 'zerotest'), '删除后不再下发');
    const reAdd = await req('POST', '/api/word', { bookId: 'book-1', word: 'zerotest', meaning: '回来了' }, auth);
    assert.ok(reAdd.json.ok, '重新添加成功');
    const afterRe = await req('GET', '/api/sync?book=book-1&since=0', null, auth);
    assert.ok(afterRe.json.words.some((x) => x.word === 'zerotest'), '重加后词仍在下发');
    assert.ok(!afterRe.json.tombstones.some((t) => t.word === 'zerotest'), '重加清除了墓碑');
  }

  // 设备只能删自己
  assert.strictEqual((await req('DELETE', '/api/device/other-device', null, auth)).status, 403, '不能删别的设备');
  assert.strictEqual((await req('DELETE', '/api/device/' + pairRes.json.deviceId, null, auth)).status, 200, '能删自己');

  await serverBox.stop();
  console.log('ALL SYNC TESTS PASSED');
  process.exit(0);
})().catch((e) => {
  console.error('TEST FAILED:', e.message);
  process.exit(1);
});
