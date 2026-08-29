/**
 * 生成简单的 32x32 托盘图标（assets/tray-icon.png）。
 * 黄色方块 + 黑描边 + 两个眼睛 + 嘴巴，新野兽派风格。
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function crc32(buf) {
  let table = crc32.table;
  if (!table) {
    table = crc32.table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
  }
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

const W = 32;
const H = 32;
const pixels = Buffer.alloc(W * H * 4);

function setPixel(x, y, r, g, b, a = 255) {
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 4;
  pixels[i] = r;
  pixels[i + 1] = g;
  pixels[i + 2] = b;
  pixels[i + 3] = a;
}

// 背景黄色，黑描边
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const border = x < 2 || x >= W - 2 || y < 2 || y >= H - 2;
    if (border) setPixel(x, y, 0, 0, 0);
    else setPixel(x, y, 255, 216, 77);
  }
}

// 眼睛（3x3 黑色方块）
for (let ey = 12; ey <= 14; ey++) {
  for (let ex = 8; ex <= 10; ex++) setPixel(ex, ey, 0, 0, 0);
  for (let ex = 21; ex <= 23; ex++) setPixel(ex, ey, 0, 0, 0);
}

// 嘴巴（一条横线 + 两端圆弧）
for (let x = 12; x <= 19; x++) setPixel(x, 21, 0, 0, 0);
for (let x = 10; x <= 13; x++) setPixel(x, 20, 0, 0, 0);
for (let x = 18; x <= 21; x++) setPixel(x, 20, 0, 0, 0);

// 组装 PNG
const raw = Buffer.alloc(H * (W * 4 + 1));
for (let y = 0; y < H; y++) {
  raw[y * (W * 4 + 1)] = 0; // filter: none
  pixels.copy(raw, y * (W * 4 + 1) + 1, y * W * 4, (y + 1) * W * 4);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0);
ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8;   // bit depth
ihdr[9] = 6;   // RGBA
ihdr[10] = 0;
ihdr[11] = 0;
ihdr[12] = 0;

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw)),
  chunk('IEND', Buffer.alloc(0))
]);

const out = path.join(__dirname, '..', 'assets', 'tray-icon.png');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, png);
console.log('已生成 ' + out + '（' + png.length + ' bytes）');
