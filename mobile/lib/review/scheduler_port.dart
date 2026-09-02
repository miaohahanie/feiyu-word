import '../models/word.dart';

/// 与 renderer/scheduler.js、sync/scheduler.js 保持一致的 SM-2 移植版。
/// 修改此处时必须同步电脑端两处实现，并运行 test/scheduler_port_test.dart。
const int _dayMs = 24 * 60 * 60 * 1000;
const int _minMs = 60 * 1000;

int mapRatingToQuality(int rating) {
  final r = rating.clamp(0, 10);
  if (r <= 1) return 1;
  if (r <= 3) return 2;
  if (r <= 5) return 3;
  if (r <= 7) return 4;
  return 5;
}

Word applyRating(Word word, int rating, int now, String eventId) {
  final q = mapRatingToQuality(rating);
  final r = rating.clamp(0, 10);

  if (word.ease < 1.3) word.ease = 2.5;
  if (word.reps < 0) word.reps = 0;
  if (word.interval < 0) word.interval = 0;
  if (word.lapses < 0) word.lapses = 0;

  if (q < 3) {
    // 遗忘：重置次数，短时间后再出现
    word.reps = 0;
    word.lapses += 1;
    word.interval = 0;
    word.nextReview = now + (r <= 1 ? 10 * _minMs : 4 * 60 * _minMs);
  } else {
    word.reps += 1;
    if (word.reps == 1) {
      word.interval = 1;
    } else if (word.reps == 2) {
      word.interval = 6;
    } else {
      word.interval = (word.interval * word.ease).round().clamp(1, 1000000);
    }
    word.nextReview = now + word.interval * _dayMs;
    final efDelta = 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
    word.ease = (word.ease + efDelta).clamp(1.3, 99.0);
  }

  word.lastRating = r;
  word.updatedAt = now;
  word.history.add(HistoryItem(id: eventId, createdAt: now, rating: r));

  // 与电脑端一致：最近 3 次自评 >= 8 且当前间隔 >= 21 天 → 已掌握
  final recent = word.history.length >= 3
      ? word.history.sublist(word.history.length - 3)
      : word.history;
  if (recent.length >= 3 && recent.every((h) => h.rating >= 8) && word.interval >= 21) {
    word.mastered = true;
  } else if (r <= 2) {
    word.mastered = false;
  }

  return word;
}
