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

  test('Q5 连续高分：1天→6天→interval*ease，且到达21天后已掌握', () {
    final w = newWord();

    applyRating(w, 8, now, 'e1');
    expect(w.reps, 1);
    expect(w.interval, 1);
    expect(w.nextReview, now + 1 * 24 * 60 * 60 * 1000);
    expect(w.ease, 2.6);

    applyRating(w, 8, now + 1000, 'e2');
    expect(w.reps, 2);
    expect(w.interval, 6);
    expect(w.ease, 2.7);

    applyRating(w, 8, now + 2000, 'e3');
    expect(w.reps, 3);
    expect(w.interval, 16); // round(6 * 2.7)
    expect(w.mastered, false);

    applyRating(w, 8, now + 3000, 'e4');
    expect(w.interval, 45); // round(16 * 2.8)
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

  test('Q3 模糊：ease 下降 0.14', () {
    final w = newWord();
    applyRating(w, 5, now, 'e1');
    expect(w.ease, 2.36);
    expect(w.reps, 1);
    expect(w.interval, 1);
  });

  test('历史记录写入与读取', () {
    final w = newWord();
    applyRating(w, 8, now, 'evt-1');
    expect(w.history.length, 1);
    expect(w.history.first.id, 'evt-1');
    expect(w.history.first.rating, 8);
  });
}
