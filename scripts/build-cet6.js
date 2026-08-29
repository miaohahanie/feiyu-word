/**
 * 从 cet-words-cli 包（MIT）的 words.json 提取 CET-6 词表，
 * 生成 renderer/cet6-data.js 供内置六级词汇本使用。
 */
const fs = require('fs');
const path = require('path');

const srcPath = path.join(__dirname, '..', '.tmp', 'package', 'data', 'words.json');
const outPath = path.join(__dirname, '..', 'renderer', 'cet6-data.js');

if (!fs.existsSync(srcPath)) {
  console.error('[build-cet6] 未找到 ' + srcPath);
  console.error('请先执行: npm pack cet-words-cli --json && tar 解压到 .tmp/package');
  process.exit(1);
}

const words = JSON.parse(fs.readFileSync(srcPath, 'utf8'));
const cet6 = words.filter((w) => w.level === 'cet6');

const rows = cet6.map((w) => {
  const meaning = (w.definitions || [])
    .map((d) => (d.pos ? d.pos + ' ' : '') + (d.zh || ''))
    .filter(Boolean)
    .join('；');
  const phonetic = w.phoneticUS || w.phoneticUK || '';
  return [w.word, meaning, phonetic, w.frequency || 0];
});

const out =
  '// 内置六级词表（来源：cet-words-cli 0.3.1，MIT License；词条数 ' + rows.length + '）\n' +
  '// 格式：[单词, 中文释义, 音标, 词频]\n' +
  'window.CET6_WORDS = ' +
  JSON.stringify(rows, null, 0) +
  ';\n' +
  'window.CET6_WORDS_COUNT = ' +
  rows.length +
  ';\n';

fs.writeFileSync(outPath, out, 'utf8');
console.log('已生成 ' + outPath + '，CET-6 词条数：' + rows.length);
