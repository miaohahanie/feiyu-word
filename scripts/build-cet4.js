/**
 * 从 renderer/dict-data.js 的完整离线词典（CET4 + CET6，5760 词）中
 * 提取 CET-4 词表，生成 renderer/cet4-data.js 供内置四级词汇本使用。
 *
 * 数据源与 dict-data.js / cet6-data.js 一致（cet-words-cli，MIT License）。
 */
const fs = require('fs');
const path = require('path');

const dictPath = path.join(__dirname, '..', 'renderer', 'dict-data.js');
const outPath = path.join(__dirname, '..', 'renderer', 'cet4-data.js');

if (!fs.existsSync(dictPath)) {
  console.error('[build-cet4] 未找到 ' + dictPath);
  process.exit(1);
}

// 在 Node 环境读取 dict-data.js（它把数据挂到 window.DICT_WORDS 上）
global.window = {};
eval(fs.readFileSync(dictPath, 'utf8'));

const all = window.DICT_WORDS || [];
const cet4 = all.filter((row) => String(row[4] || '').toLowerCase() === 'cet4');

// 与 cet6-data.js 保持一致：[单词, 中文释义, 音标, 词频]
const rows = cet4.map((row) => [row[0], row[1], row[2], row[3] || 0]);

const out =
  '// 内置四级词表（来源：cet-words-cli 0.3.1，MIT License；词条数 ' + rows.length + '）\n' +
  '// 格式：[单词, 中文释义, 音标, 词频]\n' +
  'window.CET4_WORDS = ' +
  JSON.stringify(rows, null, 0) +
  ';\n' +
  'window.CET4_WORDS_COUNT = ' +
  rows.length +
  ';\n';

fs.writeFileSync(outPath, out, 'utf8');
console.log('已生成 ' + outPath + '，CET-4 词条数：' + rows.length);
