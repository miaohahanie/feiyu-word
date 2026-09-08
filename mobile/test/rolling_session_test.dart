import 'package:flutter_test/flutter_test.dart';
import 'package:word_pet_mobile/models/word.dart';
import 'package:word_pet_mobile/review/rolling_session.dart';

Word word(String text) => Word(bookId: 'book-test', word: text, meaning: 'x');

void main() {
  test('fromServerJson 解析服务端 history（{id,date,rating}）', () {
    final w = Word.fromServerJson('b1', {
      'word': 'apple',
      'meaning': '苹果',
      'history': [
        {'id': 'evt-1', 'date': '2026-01-01T08:00:00.000Z', 'rating': 8},
        {'id': null, 'date': '', 'rating': 4},
      ],
    });

    expect(w.history.length, 2);
    expect(w.history[0].id, 'evt-1');
    expect(w.history[0].rating, 8);
    expect(w.history[0].createdAt,
        DateTime.utc(2026, 1, 1, 8).millisecondsSinceEpoch);
    expect(w.history[1].id, '');
    expect(w.history[1].createdAt, 0);
    expect(w.history[1].rating, 4);
  });

  test('fromServerJson 无 history 字段时安全降级', () {
    final w = Word.fromServerJson('b1', {'word': 'cat', 'meaning': '猫'});
    expect(w.history, isEmpty);
    expect(w.meaning, '猫');
  });


  test('首轮全部认识：一轮结束，不再滚动', () {
    final s = RollingSession([word('a'), word('b'), word('c')]);

    expect(s.round, 1);
    expect(s.totalWords, 3);
    expect(s.remaining, 3);
    expect(s.finished, false);
    expect(s.current, isNotNull);

    expect(s.grade(8), false);
    expect(s.remaining, 2);
    expect(s.grade(8), false);
    expect(s.remaining, 1);
    expect(s.grade(8), true);

    expect(s.finished, true);
    expect(s.current, isNull);
    expect(s.remaining, 0);
    expect(s.round, 1);
  });

  test('模糊/不认识留到下一轮，直到全部认识', () {
    final a = word('a');
    final b = word('b');
    final s = RollingSession([a, b]);

    // 第一轮：a 认识，b 模糊
    final first = s.current!;
    s.grade(first == a ? 8 : 4);
    s.grade(s.current == b ? 4 : 8);

    expect(s.finished, false);
    expect(s.round, 2);
    expect(s.remaining, 1);
    expect(s.roundTotal, 1);
    expect(s.roundDone, 0);
    expect(s.current, b);

    // 第二轮：b 认识 → 结束
    expect(s.grade(8), true);
    expect(s.finished, true);
  });

  test('多轮滚动：每轮未通过的词进入下一轮', () {
    final a = word('a');
    final s = RollingSession([a]);

    expect(s.grade(1), false); // 第 1 轮不认识
    expect(s.round, 2);
    expect(s.current, a);
    expect(s.grade(4), false); // 第 2 轮模糊
    expect(s.round, 3);
    expect(s.current, a);
    expect(s.grade(8), true); // 第 3 轮认识
    expect(s.round, 3);
  });

  test('skip 视作未通过，进入下一轮', () {
    final a = word('a');
    final s = RollingSession([a]);

    s.skip();
    expect(s.finished, false);
    expect(s.round, 2);
    expect(s.current, a);

    expect(s.grade(8), true);
  });

  test('结束后继续评分是安全的 no-op', () {
    final s = RollingSession([word('a')]);
    expect(s.grade(8), true);
    expect(s.grade(1), true);
    expect(s.round, 1);
  });

  test('空队列抛出 ArgumentError', () {
    expect(() => RollingSession([]), throwsArgumentError);
  });

  test('同一轮内词数与进度计数正确', () {
    final s = RollingSession([word('a'), word('b'), word('c'), word('d')]);
    expect(s.roundTotal, 4);

    s.grade(8);
    expect(s.roundDone, 1);
    s.grade(4);
    expect(s.roundDone, 2);
    expect(s.remaining, 3); // 2 个未作答 + 1 个进入下一轮
  });
}
