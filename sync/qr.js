/**
 * 二维码生成（qrcode npm 包，MIT）。
 */
'use strict';

const QRCode = require('qrcode');

function buildPairUrl(ip, port, code) {
  return `wordpet://pair?host=${encodeURIComponent(ip)}&port=${Number(port)}&code=${encodeURIComponent(code)}`;
}

async function makePairQrDataUrl(ip, port, code) {
  return QRCode.toDataURL(buildPairUrl(ip, port, code), {
    width: 220,
    margin: 1,
    errorCorrectionLevel: 'M'
  });
}

module.exports = { buildPairUrl, makePairQrDataUrl };
