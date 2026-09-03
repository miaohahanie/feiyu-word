import 'package:uuid/uuid.dart';

import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import '../models/review_event.dart';
import '../models/word.dart';
import '../review/scheduler_port.dart';
import 'pairing_service.dart';
import 'sync_client.dart';

class SyncResult {
  final bool ok;
  final String message;
  final int pulled;
  final int pushed;
  final int changed;

  const SyncResult({
    required this.ok,
    required this.message,
    this.pulled = 0,
    this.pushed = 0,
    this.changed = 0,
  });
}

class SyncService {
  final PairingService pairing;
  final WordRepository repository;
  final SettingsRepository settings;
  final String deviceId;
  final String bookId;

  static const _uuid = Uuid();

  SyncService({
    required this.pairing,
    required this.repository,
    required this.settings,
    required this.deviceId,
    required this.bookId,
  });

  Future<SyncResult> sync() async {
    final client = await pairing.buildClient();
    if (client == null) {
      return const SyncResult(ok: false, message: '尚未配对');
    }

    try {
      final cursorKey = 'cursor.$bookId';
      final since = await repository.getSyncCursor(cursorKey) ?? 0;

      // 1) 拉取增量词库
      final pull = await client.pull(bookId, since);
      await repository.upsertWords(pull.words);
      if (pull.tombstones.isNotEmpty) {
        await repository.removeWords(bookId, pull.tombstones);
      }

      // 2) 上传未同步的复习事件；服务端用同一套 SM-2 重算并回传权威状态
      final pending = await repository.getPendingEvents();
      final incoming = pending.where((e) => e.bookId == bookId).toList();
      int pushed = 0;
      int changed = 0;
      if (incoming.isNotEmpty) {
        final push = await client.push(incoming);
        pushed = push.accepted;
        changed = push.changedWords.length;
        await repository.upsertWords(push.changedWords);
        await repository.markEventsSynced(incoming.map((e) => e.eventId).toList());
      }

      // 3) 记录服务端游标
      final serverTime =
          pull.serverTime > 0 ? pull.serverTime : DateTime.now().millisecondsSinceEpoch;
      await repository.setSyncCursor(cursorKey, serverTime);

      return SyncResult(
        ok: true,
        message: '同步完成',
        pulled: pull.words.length,
        pushed: pushed,
        changed: changed,
      );
    } catch (e) {
      return SyncResult(ok: false, message: '同步失败：$e');
    }
  }

  /// 本地评分：用与电脑端一致的 SM-2 算法更新词条状态，并写入待上传事件。
  Future<ReviewEvent> review(Word word, int rating) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final event = ReviewEvent(
      eventId: _uuid.v4(),
      deviceId: deviceId,
      bookId: bookId,
      word: word.word,
      rating: rating,
      createdAt: now,
    );

    applyRating(word, rating, now, event.eventId);
    await repository.updateWord(word);
    await repository.saveReviewEvent(event);
    return event;
  }

  /// 在线查词（走电脑端同步服务的 /api/lookup）
  Future<LookupResult> lookupWord(String word) async {
    final client = await pairing.buildClient();
    if (client == null) throw Exception('尚未配对');
    return client.lookup(word);
  }

  /// 添加单词到当前词本：电脑端入库 + 手机本地入库。
  Future<Word> addWord(String word, {String? meaning, String? phonetic}) async {
    final client = await pairing.buildClient();
    if (client == null) throw Exception('尚未配对');
    final serverWord = await client.addWord(
      bookId: bookId,
      word: word,
      meaning: meaning,
      phonetic: phonetic,
    );
    await repository.upsertWords([serverWord]);
    return serverWord;
  }
}
