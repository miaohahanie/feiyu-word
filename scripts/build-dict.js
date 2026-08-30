/**
 * 从 cet-words-cli 包（MIT）的 words.json 生成完整离线词典
 * renderer/dict-data.js（CET4 + CET6，共 5760 词）。
 */
const fs = require('fs');
const path = require('path');

const srcPath = path.join(__dirname, '..', '.tmp', 'package', 'data', 'words.json');
const outPath = path.join(__dirname, '..', 'renderer', 'dict-data.js');

if (!fs.existsSync(srcPath)) {
  console.error('[build-dict] 未找到 ' + srcPath);
  console.error('请先执行: npm pack cet-words-cli --json && tar 解压到 .tmp/package');
  process.exit(1);
}

const words = JSON.parse(fs.readFileSync(srcPath, 'utf8'));

const rows = words.map((w) => {
  const meaning = (w.definitions || [])
    .map((d) => (d.pos ? d.pos + ' ' : '') + (d.zh || ''))
    .filter(Boolean)
    .join('；');
  const phonetic = w.phoneticUS || w.phoneticUK || '';
  return [w.word, meaning, phonetic, w.frequency || 0, w.level || ''];
});

const out =
  '// 内置离线词典（来源：cet-words-cli 0.3.1，MIT License；词条数 ' + rows.length + '）\n' +
  '// 格式：[单词, 中文释义, 音标, 词频, 等级(cet4/cet6)]\n' +
  'window.DICT_WORDS = ' +
  JSON.stringify(rows, null, 0) +
  ';\n' +
  'window.DICT_WORDS_COUNT = ' +
  rows.length +
  ';\n';

fs.writeFileSync(outPath, out, 'utf8');
console.log('已生成 ' + outPath + '，词条数：' + rows.length);
