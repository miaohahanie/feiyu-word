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
      // 0) 刷新词本列表：桌面端新增/删除词本也能到达手机。
      //    失败不阻塞词库同步（老版本服务端可能没有该接口）。
      try {
        final serverBooks = await client.fetchBooks();
        await repository.upsertBooks(serverBooks);
        await repository.removeBooksNotIn(serverBooks.map((b) => b.id).toList());
      } catch (_) {}

      final cursorKey = 'cursor.$bookId';
      final since = await repository.getSyncCursor(cursorKey) ?? 0;

      // 1) 拉取增量词库。先应用墓碑再 upsert：
      //    “删除后重加”的词在墓碑与词并存时不会被旧墓碑误删。
      final pull = await client.pull(bookId, since);
      if (pull.tombstones.isNotEmpty) {
        await repository.removeWords(bookId, pull.tombstones);
      }
      await repository.upsertWords(pull.words);

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
    } finally {
      client.close();
    }
  }

  /// 本地评分：用与电脑端一致的 SM-2 算法更新词条状态，并写入待上传事件。
  Future<ReviewEvent> review(Word word, int rating) async {
    final event = applyReviewLocally(word, rating);
    await persistReview(word, event);
    return event;
  }

  /// 同步部分：只改内存中的词条状态并生成事件，UI 可立即切卡。
  ReviewEvent applyReviewLocally(Word word, int rating) {
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
    return event;
  }

  /// 异步部分：落库（词条状态 + 待上传事件）。
  Future<void> persistReview(Word word, ReviewEvent event) async {
    await repository.updateWord(word);
    await repository.saveReviewEvent(event);
  }

  /// 在线查词（走电脑端同步服务的 /api/lookup）
  Future<LookupResult> lookupWord(String word) async {
    final client = await pairing.buildClient();
    if (client == null) throw Exception('尚未配对');
    try {
      return await client.lookup(word);
    } finally {
      client.close();
    }
  }

  /// 添加单词到当前词本：电脑端入库 + 手机本地入库。
  Future<Word> addWord(String word, {String? meaning, String? phonetic}) async {
    final client = await pairing.buildClient();
    if (client == null) throw Exception('尚未配对');
    try {
      final serverWord =
          await client.addWord(bookId: bookId, word: word, meaning: meaning, phonetic: phonetic);
      await repository.upsertWords([serverWord]);
      return serverWord;
    } finally {
      client.close();
    }
  }

  /// 从当前词本删除单词：电脑端删除 + 手机本地删除。
  Future<void> deleteWord(String word) async {
    final client = await pairing.buildClient();
    if (client == null) throw Exception('尚未配对');
    try {
      await client.deleteWord(bookId: bookId, word: word);
      await repository.deleteWord(bookId, word);
    } finally {
      client.close();
    }
  }
}
