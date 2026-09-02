import 'package:flutter/foundation.dart';

import 'data/settings_repository.dart';
import 'data/word_repository.dart';
import 'models/book.dart';
import 'sync/pairing_service.dart';
import 'sync/sync_service.dart';

class AppState extends ChangeNotifier {
  final WordRepository repository;
  final SettingsRepository settings;
  final PairingService pairing;

  List<Book> books = [];
  String? selectedBookId;
  bool paired = false;
  bool syncing = false;
  String lastMessage = '';
  DateTime? lastSyncAt;

  AppState({
    required this.repository,
    required this.settings,
    required this.pairing,
  });

  Future<void> init() async {
    await refreshBooks();
    final saved = await settings.getString('app.selectedBookId');
    if (saved != null && books.any((b) => b.id == saved)) {
      selectedBookId = saved;
    } else if (books.isNotEmpty) {
      selectedBookId = books.first.id;
    }
    paired = await pairing.hasPaired();
    notifyListeners();
  }

  Future<void> refreshBooks() async {
    books = await repository.getBooks();
    notifyListeners();
  }

  Future<void> selectBook(String id) async {
    selectedBookId = id;
    await settings.setString('app.selectedBookId', id);
    notifyListeners();
  }

  void markPaired() {
    paired = true;
    notifyListeners();
  }

  void markUnpaired() {
    paired = false;
    lastMessage = '';
    notifyListeners();
  }

  Future<SyncResult> syncNow() async {
    if (selectedBookId == null) {
      return const SyncResult(ok: false, message: '请先选择词本');
    }
    final service = SyncService(
      pairing: pairing,
      repository: repository,
      settings: settings,
      deviceId: (await settings.getString('sync.deviceId')) ?? '',
      bookId: selectedBookId!,
    );
    syncing = true;
    notifyListeners();
    final result = await service.sync();
    syncing = false;
    lastMessage = result.message;
    if (result.ok) lastSyncAt = DateTime.now();
    notifyListeners();
    return result;
  }

  Future<int> dueCount() async {
    if (selectedBookId == null) return 0;
    return repository.countDueWords(selectedBookId!, DateTime.now().millisecondsSinceEpoch);
  }
}
