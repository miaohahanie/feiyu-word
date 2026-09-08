import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/review_event.dart';
import '../models/word.dart';
import 'app_database.dart';

class WordRepository {
  Future<Database> _db() => AppDatabase.instance.database;

  Future<void> upsertBooks(List<Book> books) async {
    final db = await _db();
    final batch = db.batch();
    for (final b in books) {
      batch.insert(
        'books',
        b.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Book>> getBooks() async {
    final db = await _db();
    final rows = await db.query('books', orderBy: 'name ASC');
    return rows.map((r) => Book.fromMap(r)).toList();
  }

  Future<void> upsertWords(List<Word> words) async {
    final db = await _db();
    final batch = db.batch();
    for (final w in words) {
      batch.insert(
        'words',
        w.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeWords(String bookId, List<String> words) async {
    final db = await _db();
    final batch = db.batch();
    for (final word in words) {
      batch.delete(
        'words',
        where: 'bookId = ? AND word = ?',
        whereArgs: [bookId, word],
      );
    }
    await batch.commit(noResult: true);
  }

  /// 词本列表对齐桌面端：删除服务端已不存在的词本及其全部单词。
  Future<void> removeBooksNotIn(List<String> keepIds) async {
    final db = await _db();
    final rows = await db.query('books', columns: ['id']);
    final keep = keepIds.toSet();
    final removed = rows
        .map((r) => r['id'] as String)
        .where((id) => !keep.contains(id))
        .toList();
    if (removed.isEmpty) return;
    final batch = db.batch();
    for (final id in removed) {
      batch.delete('books', where: 'id = ?', whereArgs: [id]);
      batch.delete('words', where: 'bookId = ?', whereArgs: [id]);
      batch.delete('review_events', where: 'bookId = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Word>> getWords(String? bookId, {String? keyword}) async {
    final db = await _db();
    final where = <String>[];
    final args = <Object>[];

    if (bookId != null && bookId.isNotEmpty) {
      where.add('bookId = ?');
      args.add(bookId);
    }
    where.add('deleted = 0');
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.add('(word LIKE ? OR meaning LIKE ?)');
      final like = '%${keyword.trim()}%';
      args.addAll([like, like]);
    }

    final rows = await db.query(
      'words',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'word ASC',
    );
    return rows.map((r) => Word.fromMap(r)).toList();
  }

  /// 按词面批量取词（保持传入顺序）。
  Future<List<Word>> getWordsByKey(String bookId, List<String> words) async {
    if (words.isEmpty) return [];
    final db = await _db();
    final placeholders = List.filled(words.length, '?').join(',');
    final rows = await db.query(
      'words',
      where: 'bookId = ? AND deleted = 0 AND word IN ($placeholders)',
      whereArgs: [bookId, ...words.map((w) => w.toLowerCase())],
    );
    final byKey = {for (final r in rows.map((r) => Word.fromMap(r))) r.word: r};
    return words.map((w) => byKey[w.toLowerCase()]).whereType<Word>().toList();
  }

  /// 今天复习过的词里，最近一次评分 ≤ 4（模糊/不认识）的词面，按复习先后排序。
  Future<List<String>> weakWordsReviewedToday(String bookId) async {
    final db = await _db();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await db.query(
      'review_events',
      columns: ['word', 'rating'],
      where: 'bookId = ? AND createdAt >= ?',
      whereArgs: [bookId, start],
      orderBy: 'createdAt ASC',
    );
    final lastRating = <String, int>{};
    for (final r in rows) {
      lastRating[r['word'] as String] = (r['rating'] as int?) ?? 0;
    }
    return lastRating.entries
        .where((e) => e.value <= 4)
        .map((e) => e.key)
        .toList();
  }

  Future<List<Word>> getDueWords(String bookId, int now) async {
    final db = await _db();
    final rows = await db.query(
      'words',
      where:
          'bookId = ? AND deleted = 0 AND mastered = 0 AND (nextReview <= 0 OR nextReview <= ?)',
      whereArgs: [bookId, now],
      orderBy: 'nextReview ASC',
    );
    return rows.map((r) => Word.fromMap(r)).toList();
  }

  Future<Word?> getWord(String bookId, String word) async {
    final db = await _db();
    final rows = await db.query(
      'words',
      where: 'bookId = ? AND word = ?',
      whereArgs: [bookId, word],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Word.fromMap(rows.first);
  }

  Future<void> updateWord(Word w) async {
    final db = await _db();
    await db.insert(
      'words',
      w.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveReviewEvent(ReviewEvent event) async {
    final db = await _db();
    await db.insert(
      'review_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReviewEvent>> getPendingEvents({int limit = 200}) async {
    final db = await _db();
    final rows = await db.query(
      'review_events',
      where: 'synced = 0',
      orderBy: 'createdAt ASC',
      limit: limit,
    );
    return rows.map((r) => ReviewEvent.fromMap(r)).toList();
  }

  Future<void> markEventsSynced(List<String> eventIds) async {
    final db = await _db();
    final batch = db.batch();
    for (final id in eventIds) {
      batch.update(
        'review_events',
        {'synced': 1},
        where: 'eventId = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int?> getSyncCursor(String key) async {
    final db = await _db();
    final rows = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return int.tryParse(rows.first['value'] as String? ?? '');
  }

  Future<void> setSyncCursor(String key, int value) async {
    final db = await _db();
    await db.insert(
      'sync_state',
      {'key': key, 'value': value.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> countDueWords(String bookId, int now) async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM words WHERE bookId = ? AND deleted = 0 AND mastered = 0 AND (nextReview <= 0 OR nextReview <= ?)',
      [bookId, now],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countTodayEvents() async {
    final db = await _db();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM review_events WHERE createdAt >= ?',
      [start],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 记录一次滚动练习会话（供学习报告统计）。
  Future<void> saveRollingSession({
    required int words,
    required int rounds,
    required bool stoppedEarly,
  }) async {
    final db = await _db();
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await db.insert('rolling_sessions', {
      'day': day,
      'words': words,
      'rounds': rounds,
      'stoppedEarly': stoppedEarly ? 1 : 0,
      'createdAt': now.millisecondsSinceEpoch,
    });
  }

  /// 最近 days 天的每日复习量（day → 次数，缺失日期表示当天没复习）。
  Future<Map<String, int>> dailyReviewCounts(int days) async {
    final db = await _db();
    final start = DateTime.now().millisecondsSinceEpoch - days * 24 * 60 * 60 * 1000;
    final rows = await db.rawQuery(
      "SELECT date(createdAt / 1000, 'unixepoch', 'localtime') AS day, COUNT(*) AS c "
      'FROM review_events WHERE createdAt >= ? GROUP BY day',
      [start],
    );
    return {
      for (final r in rows)
        (r['day'] as String): (r['c'] as int?) ?? 0,
    };
  }

  /// 最近 days 天的评分分布。
  Future<Map<int, int>> ratingDistribution(int days) async {
    final db = await _db();
    final start = DateTime.now().millisecondsSinceEpoch - days * 24 * 60 * 60 * 1000;
    final rows = await db.rawQuery(
      'SELECT rating, COUNT(*) AS c FROM review_events WHERE createdAt >= ? GROUP BY rating',
      [start],
    );
    return {
      for (final r in rows)
        ((r['rating'] as num?) ?? 0).toInt(): (r['c'] as int?) ?? 0,
    };
  }

  /// 最近 days 天的滚动练习汇总。
  Future<Map<String, double>> rollingStats(int days) async {
    final db = await _db();
    final start = DateTime.now().millisecondsSinceEpoch - days * 24 * 60 * 60 * 1000;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS sessions, AVG(rounds) AS avgRounds, SUM(words) AS words '
      'FROM rolling_sessions WHERE createdAt >= ?',
      [start],
    );
    if (rows.isEmpty) return {'sessions': 0, 'avgRounds': 0, 'words': 0};
    final r = rows.first;
    return {
      'sessions': ((r['sessions'] as num?) ?? 0).toDouble(),
      'avgRounds': ((r['avgRounds'] as num?) ?? 0).toDouble(),
      'words': ((r['words'] as num?) ?? 0).toDouble(),
    };
  }

  Future<Map<int, int>> ratingCountsToday() async {
    final db = await _db();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT rating, COUNT(*) AS c FROM review_events WHERE createdAt >= ? GROUP BY rating ORDER BY rating ASC',
      [start],
    );
    final map = <int, int>{};
    for (final r in rows) {
      map[(r['rating'] as int?) ?? 0] = (r['c'] as int?) ?? 0;
    }
    return map;
  }

  Future<void> deleteWord(String bookId, String word) async {
    final db = await _db();
    await db.delete(
      'words',
      where: 'bookId = ? AND word = ?',
      whereArgs: [bookId, word],
    );
  }
}
