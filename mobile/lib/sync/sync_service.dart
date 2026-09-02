import 'package:uuid/uuid.dart';

import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import '../models/review_event.dart';
import '../models/word.dart';
import 'pairing_service.dart';

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

      // 2) 上传未同步的复习事件
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
      final serverTime = pull.serverTime > 0 ? pull.serverTime : DateTime.now().millisecondsSinceEpoch;
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

  /// 本地评分：更新词条状态并写入待上传事件。
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

    applyLocalRating(word, rating, now);
    await repository.updateWord(word);
    await repository.saveReviewEvent(event);
    return event;
  }
}

void applyLocalRating(Word word, int rating, int now) {
  // 与 review/scheduler_port.dart 保持一致的本地估算（服务端会在同步时重算权威结果）。
  final q = mapRatingToQuality(rating);
  final r = rating.clamp(0, 10);

  if (word.ease < 1.3) word.ease = 2.5;
  if (q < 3) {
    word.reps = 0;
    word.lapses += 1;
    word.interval = 0;
    word.nextReview = now + (r <= 1 ? 10 * 60 * 1000 : 4 * 60 * 60 * 1000);
  } else {
    word.reps += 1;
    if (word.reps == 1) {
      word.interval = 1;
    } else if (word.reps == 2) {
      word.interval = 6;
    } else {
      word.interval = (word.interval * word.ease).round().clamp(1, 1000000);
    }
    word.nextReview = now + word.interval * 24 * 60 * 60 * 1000;
    final efDelta = 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
    word.ease = (word.ease + efDelta).clamp(1.3, 99.0);
  }
  word.lastRating = r;
  word.updatedAt = now;
  if (r <= 2) word.mastered = false;
}

int mapRatingToQuality(int rating) {
  final r = rating.clamp(0, 10);
  if (r <= 1) return 1;
  if (r <= 3) return 2;
  if (r <= 5) return 3;
  if (r <= 7) return 4;
  return 5;
}
