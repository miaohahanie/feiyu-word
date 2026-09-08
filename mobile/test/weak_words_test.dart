import 'package:flutter_test/flutter_test.dart';
import 'package:word_pet_mobile/models/word.dart';
import 'package:word_pet_mobile/review/weak_words.dart';

Word word({int lapses = 0, List<int> ratings = const []}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Word(
    bookId: 'b',
    word: 'w${ratings.join()}-$lapses',
    lapses: lapses,
    history: [
      for (var i = 0; i < ratings.length; i++)
        HistoryItem(id: 'e$i', createdAt: now + i, rating: ratings[i]),
    ],
  );
}

void main() {
  test('lapses >= 2 判定为易错，与最近评分无关', () {
    expect(isWeakWord(word(lapses: 2, ratings: [8, 8])), isTrue);
    expect(isWeakWord(word(lapses: 3, ratings: [8, 8, 8])), isTrue);
    expect(isWeakWord(word(lapses: 1, ratings: [8, 8])), isFalse);
    expect(isWeakWord(word(lapses: 0)), isFalse);
  });

  test('最近两次评分都 <= 4 判定为易错', () {
    expect(isWeakWord(word(ratings: [8, 4, 1])), isTrue);
    expect(isWeakWord(word(ratings: [8, 4, 4])), isTrue);
    expect(isWeakWord(word(ratings: [1, 4, 8])), isFalse);
    expect(isWeakWord(word(ratings: [4])), isFalse, reason: '只有一次评分不判定');
    expect(isWeakWord(word(ratings: [])), isFalse);
  });

  test('lapses 不足但最近连续模糊/不认识也命中', () {
    final w = word(lapses: 0, ratings: [8, 8, 8, 4, 4]);
    expect(isWeakWord(w), isTrue);
  });
}
