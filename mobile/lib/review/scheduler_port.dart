import '../models/word.dart';

/// 与 renderer/scheduler.js、sync/scheduler.js 保持一致的 SM-2 移植版。
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

  // 历史事件只存数据库，不放在 Word 里（与原实现保持一致：手机端本地仅保留状态）。
  if (r <= 2) {
    word.mastered = false;
  }

  return word;
}
