/**
 * 生成应用图标（256x256 PNG）与 Windows ICO（内嵌 PNG）。
 * 新野兽派风格：黄色方块 + 黑描边 + 眼睛 + 嘴巴。
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

function makePng(W, H, draw) {
  const pixels = Buffer.alloc(W * H * 4);
  const setPixel = (x, y, r, g, b, a = 255) => {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const i = (y * W + x) * 4;
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
    pixels[i + 3] = a;
  };
  draw(setPixel);
  const raw = Buffer.alloc(H * (W * 4 + 1));
  for (let y = 0; y < H; y++) {
    raw[y * (W * 4 + 1)] = 0;
    pixels.copy(raw, y * (W * 4 + 1) + 1, y * W * 4, (y + 1) * W * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0);
  ihdr.writeUInt32BE(H, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

function drawIcon(setPixel) {
  const W = 256;
  const H = 256;
  const border = 14;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const isBorder = x < border || x >= W - border || y < border || y >= H - border;
      if (isBorder) setPixel(x, y, 0, 0, 0);
      else setPixel(x, y, 255, 216, 77);
    }
  }
  // 眼睛
  for (let dy = 0; dy < 30; dy++) {
    for (let dx = 0; dx < 30; dx++) {
      setPixel(62 + dx, 92 + dy, 0, 0, 0);
      setPixel(164 + dx, 92 + dy, 0, 0, 0);
    }
  }
  // 嘴巴
  for (let dx = 0; dx < 64; dx++) setPixel(96 + dx, 172, 0, 0, 0);
  for (let dx = 0; dx < 40; dx++) {
    setPixel(78 + dx, 164, 0, 0, 0);
    setPixel(138 + dx, 164, 0, 0, 0);
  }
}

function makeIco(pngBuffer) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(1, 4); // count
  const entry = Buffer.alloc(16);
  entry[0] = 0;   // width 256
  entry[1] = 0;   // height 256
  entry[2] = 0;   // colors
  entry[3] = 0;   // reserved
  entry.writeUInt16LE(1, 4);  // planes
  entry.writeUInt16LE(32, 6); // bpp
  entry.writeUInt32LE(pngBuffer.length, 8); // size
  entry.writeUInt32LE(22, 12); // offset (6 + 16)
  return Buffer.concat([header, entry, pngBuffer]);
}

const png = makePng(256, 256, drawIcon);
const outDir = path.join(__dirname, '..', 'assets');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'icon.png'), png);
fs.writeFileSync(path.join(outDir, 'icon.ico'), makeIco(png));
console.log('已生成 assets/icon.png 与 assets/icon.ico');
