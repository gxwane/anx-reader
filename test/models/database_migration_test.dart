import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Idempotent Database Migration Spec', () {
    test('Scenario: Upgrading from v7 to v8 when reading_status already exists does not throw', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, version) async {
            // Create v7 schema with pre-existing reading_status
            await db.execute('''
              CREATE TABLE tb_books (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT,
                cover_path TEXT,
                file_path TEXT,
                last_read_position TEXT,
                reading_percentage REAL,
                author TEXT,
                is_deleted INTEGER,
                description TEXT,
                create_time TEXT,
                update_time TEXT,
                rating REAL,
                group_id INTEGER,
                file_md5 TEXT,
                reading_status INTEGER DEFAULT 0
              )
            ''');
            await db.execute('''
              INSERT INTO tb_books (id, title, cover_path, file_path, reading_percentage, author, is_deleted, create_time, update_time, reading_status)
              VALUES (1, 'Test Book', 'cover.png', 'test.epub', 0.96, 'Author', 0, '2026-08-30', '2026-08-30', 0)
            ''');
          },
        ),
      );

      // Now run onUpgradeDatabase from 7 to 8
      await DBHelper().onUpgradeDatabase(db, 7, 8);

      final tableInfo = await db.rawQuery('PRAGMA table_info(tb_books)');
      final columnNames = tableInfo.map((c) => c['name'] as String).toList();

      expect(columnNames, contains('reading_status'));
      expect(columnNames, contains('start_reading_time'));
      expect(columnNames, contains('finish_reading_time'));
      expect(columnNames, contains('read_count'));

      final books = await db.query('tb_books', where: 'id = ?', whereArgs: [1]);
      expect(books.first['reading_status'], 2);
      expect(books.first['read_count'], 1);

      // Upgrade again (idempotence verification)
      await DBHelper().onUpgradeDatabase(db, 7, 8);

      await db.close();
    });

    test('Scenario: addColumnIfNotExists is completely idempotent', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
      );
      await db.execute('CREATE TABLE IF NOT EXISTS test_table (id INTEGER PRIMARY KEY, col1 TEXT)');

      // Add new column
      await DBHelper.addColumnIfNotExists(db, 'test_table', 'col2', 'INTEGER DEFAULT 0');
      var info = await db.rawQuery('PRAGMA table_info(test_table)');
      expect(info.any((c) => c['name'] == 'col2'), isTrue);

      // Add same column again - should not throw and stay intact
      await DBHelper.addColumnIfNotExists(db, 'test_table', 'col2', 'INTEGER DEFAULT 0');
      info = await db.rawQuery('PRAGMA table_info(test_table)');
      expect(info.where((c) => c['name'] == 'col2').length, 1);

      await db.close();
    });
  });
}
