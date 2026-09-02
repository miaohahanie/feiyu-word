import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/review_event.dart';
import '../models/word.dart';
import 'app_database.dart';

class WordRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<void> upsertBooks(List<Book> books) async {
    final db = await _db;
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
    final rows = await _db.query('books', orderBy: 'name ASC');
    return rows.map((r) => Book.fromMap(r)).toList();
  }

  Future<void> upsertWords(List<Word> words) async {
    final db = await _db;
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
    final db = await _db;
    for (final word in words) {
      await db.delete(
        'words',
        where: 'bookId = ? AND word = ?',
        whereArgs: [bookId, word],
      );
    }
  }

  Future<List<Word>> getWords(String? bookId, {String? keyword}) async {
    final db = await _db;
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

  Future<List<Word>> getDueWords(String bookId, int now) async {
    final db = await _db;
    final rows = await db.query(
      'words',
      where: 'bookId = ? AND deleted = 0 AND mastered = 0 AND (nextReview <= 0 OR nextReview <= ?)',
      whereArgs: [bookId, now],
      orderBy: 'nextReview ASC',
    );
    return rows.map((r) => Word.fromMap(r)).toList();
  }

  Future<Word?> getWord(String bookId, String word) async {
    final rows = await _db.query(
      'words',
      where: 'bookId = ? AND word = ?',
      whereArgs: [bookId, word],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Word.fromMap(rows.first);
  }

  Future<void> updateWord(Word w) async {
    await _db.insert(
      'words',
      w.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveReviewEvent(ReviewEvent event) async {
    await _db.insert(
      'review_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReviewEvent>> getPendingEvents({int limit = 200}) async {
    final rows = await _db.query(
      'review_events',
      where: 'synced = 0',
      orderBy: 'createdAt ASC',
      limit: limit,
    );
    return rows.map((r) => ReviewEvent.fromMap(r)).toList();
  }

  Future<void> markEventsSynced(List<String> eventIds) async {
    final db = await _db;
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
    final rows = await _db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return int.tryParse(rows.first['value'] as String? ?? '');
  }

  Future<void> setSyncCursor(String key, int value) async {
    await _db.insert(
      'sync_state',
      {'key': key, 'value': value.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> countDueWords(String bookId, int now) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM words WHERE bookId = ? AND deleted = 0 AND mastered = 0 AND (nextReview <= 0 OR nextReview <= ?)',
      [bookId, now],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as int?) ?? 0;
  }
}
