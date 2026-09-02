import 'package:flutter_test/flutter_test.dart';
import 'package:word_pet_mobile/models/word.dart';
import 'package:word_pet_mobile/review/scheduler_port.dart';

Word newWord() {
  return Word(
    bookId: 'book-test',
    word: 'abandon',
    meaning: 'v. 放弃',
    nextReview: 0,
  );
}

void main() {
  const now = 1000000000000;
  const hour = 60 * 60 * 1000;
  const day = 24 * 60 * 60 * 1000;

  test('前 3 次高分按 2h/4h/8h 短间隔，之后进入 1天/6天/interval*ease，21天后已掌握', () {
    final w = newWord();

    applyRating(w, 8, now, 'e1');
    expect(w.reps, 1);
    expect(w.interval, 0);
    expect(w.nextReview, now + 2 * hour);
    expect(w.ease, closeTo(2.6, 1e-9));

    applyRating(w, 8, now + 1000, 'e2');
    expect(w.nextReview, now + 1000 + 4 * hour);
    expect(w.ease, closeTo(2.7, 1e-9));

    applyRating(w, 8, now + 2000, 'e3');
    expect(w.nextReview, now + 2000 + 8 * hour);
    expect(w.ease, closeTo(2.8, 1e-9));

    applyRating(w, 8, now + 3000, 'e4');
    expect(w.interval, 1);
    expect(w.nextReview, now + 3000 + day);

    applyRating(w, 8, now + 4000, 'e5');
    expect(w.interval, 6);
    expect(w.nextReview, now + 4000 + 6 * day);

    applyRating(w, 8, now + 5000, 'e6');
    expect(w.interval, 18); // round(6 * 3.0)
    expect(w.mastered, false);

    applyRating(w, 8, now + 6000, 'e7');
    expect(w.interval, 56); // round(18 * 3.1)
    expect(w.mastered, true);
  });

  test('Q1 遗忘：重置次数、10 分钟后再出现', () {
    final w = newWord();
    applyRating(w, 8, now, 'e1');
    applyRating(w, 8, now + 1000, 'e2');
    applyRating(w, 1, now + 2000, 'e3');

    expect(w.reps, 0);
    expect(w.lapses, 1);
    expect(w.interval, 0);
    expect(w.nextReview, now + 2000 + 10 * 60 * 1000);
  });

  test('Q3 模糊：ease 下降 0.14，仍按 2h 短间隔进入当天下一轮', () {
    final w = newWord();
    applyRating(w, 5, now, 'e1');
    expect(w.ease, closeTo(2.36, 1e-9));
    expect(w.reps, 1);
    expect(w.interval, 0);
    expect(w.nextReview, now + 2 * hour);
  });

  test('历史记录写入与读取', () {
    final w = newWord();
    applyRating(w, 8, now, 'evt-1');
    expect(w.history.length, 1);
    expect(w.history.first.id, 'evt-1');
    expect(w.history.first.rating, 8);
  });
}
