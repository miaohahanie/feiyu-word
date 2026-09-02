import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import 'sync_client.dart';

class PairingInfo {
  final String host;
  final int port;
  final String code;

  const PairingInfo({
    required this.host,
    required this.port,
    required this.code,
  });
}

class PairingService {
  final SettingsRepository settings;
  final WordRepository repository;

  PairingService({required this.settings, required this.repository});

  PairingInfo? parseQr(String raw) {
    final text = raw.trim();
    if (!text.startsWith('wordpet://')) return null;
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final query = uri.queryParameters;
    final host = query['host'];
    final port = int.tryParse(query['port'] ?? '');
    final code = query['code'];
    if (host == null || host.isEmpty || port == null || code == null || code.isEmpty) return null;
    return PairingInfo(host: host, port: port, code: code);
  }

  PairingInfo? parseManual(String host, String portText, String code) {
    final normalized = SyncClient.normalizeIp(host);
    final port = int.tryParse(portText.trim());
    if (normalized.isEmpty || port == null || port <= 0 || port > 65535) return null;
    if (code.trim().isEmpty) return null;
    return PairingInfo(host: normalized, port: port, code: code.trim());
  }

  Future<PairResult> pairWith(PairingInfo info) async {
    final result = await SyncClient.pair(host: info.host, port: info.port, code: info.code);
    await settings.setString('sync.host', info.host);
    await settings.setInt('sync.port', info.port);
    await settings.setString('sync.deviceId', result.deviceId);
    await settings.setString('sync.token', result.token);
    await repository.upsertBooks(result.books);
    return result;
  }

  Future<bool> hasPaired() async {
    final host = await settings.getString('sync.host');
    final deviceId = await settings.getString('sync.deviceId');
    final token = await settings.getString('sync.token');
    final port = await settings.getInt('sync.port');
    return host != null && host.isNotEmpty && deviceId != null && token != null && port != null;
  }

  Future<SyncClient?> buildClient() async {
    if (!await hasPaired()) return null;
    final host = await settings.getString('sync.host');
    final port = await settings.getInt('sync.port');
    final deviceId = await settings.getString('sync.deviceId');
    final token = await settings.getString('sync.token');
    if (host == null || port == null || deviceId == null || token == null) return null;
    return SyncClient(host: host, port: port, deviceId: deviceId, token: token);
  }

  Future<void> unpair() async {
    await settings.remove('sync.host');
    await settings.remove('sync.port');
    await settings.remove('sync.deviceId');
    await settings.remove('sync.token');
  }
}
