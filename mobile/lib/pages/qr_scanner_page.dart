import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../sync/pairing_service.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _controller = MobileScannerController();
  String _message = '请将手机对准电脑「手机同步」页面的二维码';

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    await _controller.stop();
    if (!mounted) return;
    final pairing = context.read<PairingService>();
    final state = context.read<AppState>();
    final info = pairing.parseQr(raw);
    if (info == null) {
      setState(() => _message = '二维码格式不正确，请扫描电脑端「手机同步」二维码');
      return;
    }
    try {
      final result = await pairing.pairWith(info);
      state.markPaired();
      await state.refreshBooks();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配对成功：${result.deviceId.substring(0, 8)}…')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = '配对失败：$e');
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码配对')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_message, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
