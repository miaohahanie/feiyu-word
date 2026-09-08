import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, 'word_pet_mobile.db');
    _db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 新增本地复习历史，用于“最近 3 次高分且间隔>=21天”的已掌握判断
      await db.execute("ALTER TABLE words ADD COLUMN historyJson TEXT DEFAULT '[]'");
    }
    if (oldVersion < 3) {
      // 滚动练习记录，供学习报告统计
      await db.execute('''
        CREATE TABLE IF NOT EXISTS rolling_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          day TEXT NOT NULL,
          words INTEGER NOT NULL,
          rounds INTEGER NOT NULL,
          stoppedEarly INTEGER NOT NULL DEFAULT 0,
          createdAt INTEGER NOT NULL
        )
      ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        builtin INTEGER DEFAULT 0,
        count INTEGER DEFAULT 0,
        updatedAt INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE words (
        bookId TEXT NOT NULL,
        word TEXT NOT NULL,
        meaning TEXT DEFAULT '',
        phonetic TEXT DEFAULT '',
        examplesJson TEXT DEFAULT '[]',
        historyJson TEXT DEFAULT '[]',
        reps INTEGER DEFAULT 0,
        ease REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 0,
        lapses INTEGER DEFAULT 0,
        lastRating INTEGER,
        nextReview INTEGER DEFAULT 0,
        mastered INTEGER DEFAULT 0,
        deleted INTEGER DEFAULT 0,
        updatedAt INTEGER DEFAULT 0,
        PRIMARY KEY (bookId, word)
      )
    ''');

    await db.execute('CREATE INDEX idx_words_due ON words(bookId, nextReview)');

    await db.execute('''
      CREATE TABLE review_events (
        eventId TEXT PRIMARY KEY,
        deviceId TEXT NOT NULL,
        bookId TEXT NOT NULL,
        word TEXT NOT NULL,
        rating INTEGER NOT NULL,
        createdAt INTEGER NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rolling_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day TEXT NOT NULL,
        words INTEGER NOT NULL,
        rounds INTEGER NOT NULL,
        stoppedEarly INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
