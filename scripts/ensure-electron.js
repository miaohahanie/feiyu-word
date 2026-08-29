/**
 * 确保 Electron 二进制已下载。
 * 首次 npm install 或删除 node_modules 后，npm 可能未自动下载 Electron 二进制，
 * 本脚本在 postinstall 与 start 前运行，通过 npmmirror 补齐。
 */
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.join(__dirname, '..');
const dist = path.join(root, 'node_modules', 'electron', 'dist');
const exe = path.join(dist, 'electron.exe');
const installJs = path.join(root, 'node_modules', 'electron', 'install.js');

if (fs.existsSync(exe)) {
  process.exit(0);
}

if (!fs.existsSync(installJs)) {
  console.error('[ensure-electron] electron 未安装，请先执行 npm install');
  process.exit(1);
}

const mirror = process.env.ELECTRON_MIRROR || 'https://npmmirror.com/mirrors/electron/';
console.log('[ensure-electron] 正在下载 Electron 二进制（镜像：' + mirror + '）...');

const result = spawnSync(process.execPath, [installJs], {
  stdio: 'inherit',
  env: Object.assign({}, process.env, { ELECTRON_MIRROR: mirror })
});

if (result.status === 0 && fs.existsSync(exe)) {
  process.exit(0);
}
console.error('[ensure-electron] Electron 二进制下载失败，请检查网络后重试');
process.exit(1);
