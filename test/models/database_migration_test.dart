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
    Future<Map<String, Object?>> schemaSignature(Database db) async {
      Future<List<Map<String, Object?>>> columns(String table) async {
        final rows = await db.rawQuery('PRAGMA table_info($table)');
        return rows
            .map((row) => <String, Object?>{
                  'name': row['name'],
                  'type': row['type'],
                  'notnull': row['notnull'],
                  'default': row['dflt_value'],
                  'pk': row['pk'],
                })
            .toList();
      }

      Future<List<String>> uniqueIndexColumns(String table) async {
        final indexes = await db.rawQuery('PRAGMA index_list($table)');
        final result = <String>[];
        for (final index in indexes.where((row) => row['unique'] == 1)) {
          final name = index['name'] as String;
          final details = await db.rawQuery('PRAGMA index_info($name)');
          result.add(details.map((row) => row['name']).join(','));
        }
        return result..sort();
      }

      return {
        'notes': await columns('tb_notes'),
        'readingTimes': await columns('tb_reading_time'),
        'noteIndices': await uniqueIndexColumns('tb_notes'),
        'readingTimeIndices': await uniqueIndexColumns('tb_reading_time'),
      };
    }

    Future<Database> createFreshV9() async {
      return databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: currentDbVersion,
          singleInstance: false,
          onCreate: (db, version) async {
            DBHelper.setDatabaseForTesting(db);
            await DBHelper().onUpgradeDatabase(db, 0, version);
          },
        ),
      );
    }

    Future<Database> createCleanV8AndUpgrade() async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      // Faithful baseline v8 layout: reader_note was appended after
      // update_time by the historical migration, never placed mid-table.
      await db.execute('''
        CREATE TABLE tb_notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER,
          content TEXT,
          cfi TEXT,
          chapter TEXT,
          type TEXT,
          color TEXT,
          create_time TEXT,
          update_time TEXT,
          reader_note TEXT
        )
      ''');
      await db.execute(createReadingTimeSQL);
      await DBHelper().onUpgradeDatabase(db, 8, currentDbVersion);
      return db;
    }

    test('Scenario: fresh v9 and clean v8 upgrade have identical identity constraints',
        () async {
      final fresh = await createFreshV9();
      final upgraded = await createCleanV8AndUpgrade();
      addTearDown(() async {
        DBHelper.setDatabaseForTesting(null);
        await fresh.close();
        await upgraded.close();
      });

      final freshSchema = await schemaSignature(fresh);
      final upgradedSchema = await schemaSignature(upgraded);

      expect(upgradedSchema, freshSchema);
      expect(freshSchema['noteIndices'], contains('book_id,cfi'));
      expect(freshSchema['readingTimeIndices'], contains('book_id,date'));
    });

    test('Scenario: v9 rejects duplicate note and reading-time identities',
        () async {
      final db = await createFreshV9();
      addTearDown(() async {
        DBHelper.setDatabaseForTesting(null);
        await db.close();
      });

      await db.insert('tb_notes', {'book_id': 7, 'cfi': 'same'});
      await expectLater(
        db.insert('tb_notes', {'book_id': 7, 'cfi': 'same'}),
        throwsA(isA<DatabaseException>()),
      );

      await db.insert('tb_reading_time', {
        'book_id': 7,
        'date': '2026-09-16',
        'reading_time': 10,
      });
      await expectLater(
        db.insert('tb_reading_time', {
          'book_id': 7,
          'date': '2026-09-16',
          'reading_time': 20,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('Scenario: upgrading v7 with reading_status already present reaches v9 idempotently', () async {
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
            await db.execute('''
              CREATE TABLE tb_notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                book_id INTEGER,
                content TEXT,
                cfi TEXT,
                chapter TEXT,
                type TEXT,
                color TEXT,
                reader_note TEXT,
                create_time TEXT,
                update_time TEXT
              )
            ''');
            await db.execute(createReadingTimeSQL);
          },
        ),
      );

      await DBHelper().onUpgradeDatabase(db, 7, currentDbVersion);

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
      await DBHelper().onUpgradeDatabase(db, 7, currentDbVersion);

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
