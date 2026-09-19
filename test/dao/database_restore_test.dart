import 'dart:io';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/dao/database_restore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class RestoreProbe implements Database {
  RestoreProbe(this.delegate);

  final Database delegate;
  int transactions = 0;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action,
          {bool? exclusive}) =>
      delegate.transaction((txn) async {
        transactions++;
        return action(txn);
      }, exclusive: exclusive);

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) =>
      delegate.rawQuery(sql, arguments);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Database live;
  late String backupPath;

  Future<void> createTargetSchema(Database db) async {
    await db.execute(createBookSQL);
    for (final column in [
      'rating REAL',
      'group_id INTEGER',
      'file_md5 TEXT',
      'reading_status INTEGER DEFAULT 0',
      'start_reading_time TEXT',
      'finish_reading_time TEXT',
      'read_count INTEGER DEFAULT 0',
    ]) {
      await db.execute('ALTER TABLE tb_books ADD COLUMN $column');
    }
    await db.execute(createNoteSQL);
    await db.execute(createReadingTimeSQL);
    await db.execute(createThemeSQL);
    await db.execute(createStyleSQL);
    await db.execute(createGroupSQL);
    await db.execute(createNoteIdentityIndexSQL);
    await db.execute(createReadingTimeIdentityIndexSQL);
    await db.insert('tb_groups', {
      'id': 0,
      'name': 'Root',
      'parent_id': null,
      'is_deleted': 0,
      'create_time': '2026-09-01T00:00:00.000Z',
      'update_time': '2026-09-01T00:00:00.000Z',
    });
    await db.setVersion(currentDbVersion);
  }

  Future<Database> openTarget(String path) => databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          singleInstance: false,
          onCreate: (db, version) => createTargetSchema(db),
          version: currentDbVersion,
        ),
      );

  Map<String, Object?> book(int id, String title, {int groupId = 0}) => {
        'id': id,
        'title': title,
        'cover_path': 'cover/$id.png',
        'file_path': 'file/$id.epub',
        'last_read_position': '',
        'reading_percentage': 0.5,
        'author': 'author',
        'is_deleted': 0,
        'description': '',
        'rating': 0.0,
        'group_id': groupId,
        'file_md5': 'md5-$id',
        'reading_status': 1,
        'read_count': 0,
        'create_time': '2026-09-01T00:00:00.000Z',
        'update_time': '2026-09-01T00:00:00.000Z',
      };

  Future<void> expectIdentityIndices(Database db) async {
    await expectLater(
      db.insert('tb_notes', {'book_id': 2, 'cfi': 'note'}),
      completes,
    );
    await expectLater(
      db.insert('tb_notes', {'book_id': 2, 'cfi': 'note'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('tb_reading_time', {
        'book_id': 2,
        'date': '2026-09-16',
        'reading_time': 1,
      }),
      completes,
    );
    await expectLater(
      db.insert('tb_reading_time', {
        'book_id': 2,
        'date': '2026-09-16',
        'reading_time': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anx_restore_test_');
    backupPath = '${directory.path}/backup.db';
    live = await openTarget('${directory.path}/live.db');
    await live.insert('tb_books', book(1, 'original'));
    final source = await openTarget(backupPath);
    await source.insert('tb_books', book(2, 'restored'));
    await source.close();
  });

  tearDown(() async {
    if (live.isOpen) await live.close();
    await directory.delete(recursive: true);
  });

  Future<void> restore([Database? database]) => DatabaseRestore.restore(
        database ?? live,
        backupPath,
        version: currentDbVersion,
      );

  test('restores six business tables in one transaction on the live connection',
      () async {
    final source = await databaseFactoryFfi.openDatabase(backupPath);
    await source.execute('CREATE TABLE external_payload(secret TEXT)');
    await source.execute('''
      CREATE TRIGGER external_trigger AFTER INSERT ON tb_books
      BEGIN INSERT INTO external_payload(secret) VALUES ('copied'); END
    ''');
    await source.close();
    final probe = RestoreProbe(live);

    await restore(probe);

    expect(probe.transactions, 1);
    expect(live.isOpen, isTrue);
    expect((await live.query('tb_books')).single['title'], 'restored');
    expect(
      await live.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'external_payload'"),
      isEmpty,
    );
    await expectIdentityIndices(live);
  });

  test('a live constraint failure rolls back every replaced table', () async {
    await live.execute('''
      CREATE TRIGGER reject_restore BEFORE INSERT ON tb_books
      WHEN NEW.title = 'restored'
      BEGIN SELECT RAISE(ABORT, 'blocked'); END
    ''');
    final before = await live.query('tb_books');

    await expectLater(restore(), throwsA(isA<DatabaseException>()));

    expect(await live.query('tb_books'), before);
    await expectIdentityIndices(live);
  });

  test('duplicate note identities are rejected without dropping live indices',
      () async {
    final source = await databaseFactoryFfi.openDatabase(backupPath);
    await source.execute('DROP INDEX idx_notes_book_cfi');
    await source.insert('tb_notes', {'book_id': 2, 'cfi': 'dup'});
    await source.insert('tb_notes', {'book_id': 2, 'cfi': 'dup'});
    await source.close();
    final before = await live.query('tb_books');

    await expectLater(restore(), throwsA(isA<FormatException>()));

    expect(await live.query('tb_books'), before);
    await expectIdentityIndices(live);
  });

  test('duplicate reading-day identities are rejected atomically', () async {
    final source = await databaseFactoryFfi.openDatabase(backupPath);
    await source.execute('DROP INDEX idx_reading_time_book_date');
    for (final id in [1, 2]) {
      await source.insert('tb_reading_time', {
        'id': id,
        'book_id': 2,
        'date': '2026-09-16',
        'reading_time': 60,
      });
    }
    await source.close();

    await expectLater(restore(), throwsA(isA<FormatException>()));

    expect((await live.query('tb_books')).single['title'], 'original');
    await expectIdentityIndices(live);
  });

  for (final invalid in <String, Future<void> Function(Database)>{
    'empty note CFI': (source) =>
        source.insert('tb_notes', {'book_id': 2, 'cfi': ''}).then((_) {}),
    'noncanonical reading date': (source) => source.insert('tb_reading_time', {
          'book_id': 2,
          'date': '2026-09-16T10:00:00Z',
          'reading_time': 1,
        }).then((_) {}),
    'negative reading time': (source) => source.insert('tb_reading_time', {
          'book_id': 2,
          'date': '2026-09-16',
          'reading_time': -1,
        }).then((_) {}),
    'dangling group parent': (source) => source.insert('tb_groups', {
          'id': 3,
          'name': 'dangling',
          'parent_id': 99,
          'is_deleted': 0,
        }).then((_) {}),
    'dangling book group': (source) =>
        source.update('tb_books', {'group_id': 99}).then((_) {}),
  }.entries) {
    test('${invalid.key} is rejected before touching the live database',
        () async {
      final source = await databaseFactoryFfi.openDatabase(backupPath);
      await invalid.value(source);
      await source.close();
      final backupBytes = await File(backupPath).readAsBytes();

      await expectLater(restore(), throwsA(isA<FormatException>()));

      expect((await live.query('tb_books')).single['title'], 'original');
      expect(await File(backupPath).readAsBytes(), backupBytes);
    });
  }

  test('group cycles are rejected', () async {
    final source = await databaseFactoryFfi.openDatabase(backupPath);
    await source.insert('tb_groups', {
      'id': 3,
      'name': 'three',
      'parent_id': 0,
      'is_deleted': 0,
    });
    await source.insert('tb_groups', {
      'id': 4,
      'name': 'four',
      'parent_id': 3,
      'is_deleted': 0,
    });
    await source.update('tb_groups', {'parent_id': 4},
        where: 'id = 3');
    await source.close();

    await expectLater(restore(), throwsA(isA<FormatException>()));
    expect((await live.query('tb_books')).single['title'], 'original');
  });

  test('corrupt and wrong-version backups leave live data unchanged', () async {
    await File(backupPath).writeAsString('not sqlite', flush: true);
    await expectLater(restore(), throwsA(anything));
    expect((await live.query('tb_books')).single['title'], 'original');

    await File(backupPath).delete();
    final wrong = await openTarget(backupPath);
    await wrong.setVersion(currentDbVersion - 1);
    await wrong.close();
    await expectLater(restore(), throwsA(isA<FormatException>()));
    expect((await live.query('tb_books')).single['title'], 'original');
  });
}
