import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class SettingsRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<String?> get(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String key) async {
    await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<String?> getString(String key) => get(key);

  Future<void> setString(String key, String value) => set(key, value);

  Future<int?> getInt(String key) async {
    final v = await get(key);
    if (v == null) return null;
    return int.tryParse(v);
  }

  Future<void> setInt(String key, int value) => set(key, value.toString());

  Future<bool?> getBool(String key) async {
    final v = await get(key);
    if (v == null) return null;
    return v == '1' || v == 'true';
  }

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');
}
