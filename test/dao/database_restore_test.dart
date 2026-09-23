import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_group.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/dao/database_restore.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    await source.update('tb_groups', {'parent_id': 4}, where: 'id = 3');
    await source.close();

    await expectLater(restore(), throwsA(isA<FormatException>()));
    expect((await live.query('tb_books')).single['title'], 'original');
  });

  test('a historical book may keep a soft-deleted group reference', () async {
    final source = await databaseFactoryFfi.openDatabase(backupPath);
    await source.insert('tb_groups', {
      'id': 5,
      'name': 'archived',
      'parent_id': 0,
      'is_deleted': 1,
      'create_time': '2026-09-01T00:00:00.000Z',
      'update_time': '2026-09-01T00:00:00.000Z',
    });
    await source.update(
      'tb_books',
      {'group_id': 5, 'is_deleted': 1},
      where: 'id = 2',
    );
    await source.close();

    await restore();

    final restored = (await live.query('tb_books')).single;
    expect(restored['group_id'], 5);
    expect(restored['is_deleted'], 1);
    expect(
      (await live.query('tb_groups', where: 'id = 5')).single['is_deleted'],
      1,
    );
    await expectIdentityIndices(live);
  });

  test('a live book referencing a soft-deleted group is rejected', () async {
    final source = await databaseFactoryFfi.openDatabase(backupPath);
    await source.insert('tb_groups', {
      'id': 5,
      'name': 'archived',
      'parent_id': 0,
      'is_deleted': 1,
      'create_time': '2026-09-01T00:00:00.000Z',
      'update_time': '2026-09-01T00:00:00.000Z',
    });
    await source.update('tb_books', {'group_id': 5}, where: 'id = 2');
    await source.close();
    final before = await live.query('tb_books');

    await expectLater(restore(), throwsA(isA<FormatException>()));

    expect(await live.query('tb_books'), before);
    await expectIdentityIndices(live);
  });

  test(
      'a backup produced after removing a book and cleaning its empty group still restores',
      () async {
    final workflowPath = '${directory.path}/workflow.db';
    final workflow = await openTarget(workflowPath);
    DBHelper.setDatabaseForTesting(workflow);
    try {
      await workflow.insert('tb_groups', {
        'id': 5,
        'name': 'temporary',
        'parent_id': 0,
        'is_deleted': 0,
        'create_time': '2026-09-01T00:00:00.000Z',
        'update_time': '2026-09-01T00:00:00.000Z',
      });
      await workflow.insert('tb_books', book(10, 'removed', groupId: 5));
      await workflow.insert('tb_books', book(11, 'moved', groupId: 5));

      await bookDao.batchSoftDelete([10]);
      await bookDao.batchUpdateGroup([11], 0);
      await BookGroupDao().softDeleteIfEmpty(5);
    } finally {
      DBHelper.setDatabaseForTesting(null);
    }
    await workflow.close();
    await File(workflowPath).copy(backupPath);

    await restore();

    final restoredBooks = await live.query('tb_books', orderBy: 'id');
    expect(restoredBooks, hasLength(2));
    expect(restoredBooks.first['is_deleted'], 1);
    expect(restoredBooks.first['group_id'], 5);
    expect(restoredBooks.last['is_deleted'], 0);
    expect(restoredBooks.last['group_id'], 0);
    expect(
      (await live.query('tb_groups', where: 'id = 5')).single['is_deleted'],
      1,
    );
    await expectIdentityIndices(live);
  });

  group('atomic folder dissolution', () {
    late ProviderContainer container;
    late ProviderSubscription<AsyncValue<List<List<Book>>>> subscription;

    Future<void> addGroup(int id, {int parent = 0, int deleted = 0}) =>
        live.insert('tb_groups', {
          'id': id,
          'name': 'group-$id',
          'parent_id': parent,
          'is_deleted': deleted,
          'create_time': '2026-09-01T00:00:00.000Z',
          'update_time': '2026-09-01T00:00:00.000Z',
        }).then((_) {});

    Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
          for (final table in DatabaseRestore.tables)
            table: await live.query(table, orderBy: 'id'),
        };

    setUp(() async {
      SharedPreferences.setMockInitialValues(
          {'bookshelfReadingStatusFilter': 'reading'});
      await Prefs().initPrefs();
      DBHelper.setDatabaseForTesting(live);
      await addGroup(5);
      for (final id in [10, 11, 12, 13]) {
        await live.insert('tb_books', book(id, 'book-$id', groupId: 5));
      }
      await bookDao.batchSoftDelete([10]);
      await live.update('tb_books', {'reading_status': 0}, where: 'id = 13');
      container = ProviderContainer();
      subscription = container.listen(bookListProvider, (_, __) {});
      await container.read(bookListProvider.future);
    });

    tearDown(() {
      subscription.close();
      container.dispose();
      DBHelper.setDatabaseForTesting(null);
    });

    test(
        'real provider dissolves removed and filtered books into a restorable backup',
        () async {
      await live.insert('tb_notes',
          {'book_id': 10, 'cfi': 'retained', 'content': 'personal knowledge'});
      await live.insert('tb_reading_time',
          {'book_id': 10, 'date': '2026-09-23', 'reading_time': 42});
      final visible = (await container.read(bookListProvider.future))
          .singleWhere((books) => books.first.groupId == 5);
      expect(visible.map((book) => book.id).toSet(), {11, 12});
      // A stale UI book must not overwrite newer reading data during dissolution.
      await live.update('tb_books', {'reading_percentage': 0.9},
          where: 'id = 11');
      final before = await snapshot();
      await Future<void>.sync(() =>
          container.read(bookListProvider.notifier).dissolveGroup(visible));
      final after = await snapshot();
      expect(await live.query('tb_groups', where: 'id = 5'), isEmpty);
      for (final row in after['tb_books']!) {
        final original =
            before['tb_books']!.singleWhere((b) => b['id'] == row['id']);
        if (row['id'] == 1) {
          expect(row, original);
        } else {
          expect(row['group_id'], 0,
              reason:
                  'Book ${row['id']} still references the dissolved folder');
          expect({...row}..remove('update_time'),
              {...original, 'group_id': 0}..remove('update_time'));
        }
      }
      expect(after['tb_notes'], before['tb_notes']);
      expect(after['tb_reading_time'], before['tb_reading_time']);
      final closedBackup = '${directory.path}/dissolved.db';
      await live.execute('VACUUM INTO ?', [closedBackup]);
      await DatabaseRestore.restore(live, closedBackup,
          version: currentDbVersion);
      expect(await snapshot(), after);
    });

    test(
        'direct group deletion reparents live and deleted children, not grandchildren',
        () async {
      await addGroup(6, parent: 5);
      await addGroup(7, parent: 5, deleted: 1);
      await addGroup(8, parent: 6);
      await addGroup(9);
      final before = await snapshot();
      await container.read(groupDaoProvider.notifier).hardDeleteGroup(5);
      final after = await snapshot();
      for (final id in [6, 7]) {
        final original = before['tb_groups']!.singleWhere((g) => g['id'] == id);
        final row = after['tb_groups']!.singleWhere((g) => g['id'] == id);
        expect(row['parent_id'], 0);
        expect({...row}..remove('update_time'),
            {...original, 'parent_id': 0}..remove('update_time'));
      }
      for (final id in [0, 8, 9]) {
        expect(after['tb_groups']!.singleWhere((g) => g['id'] == id),
            before['tb_groups']!.singleWhere((g) => g['id'] == id));
      }
      await container.read(groupDaoProvider.notifier).hardDeleteGroup(5);
      expect(await snapshot(), after,
          reason: 'Repeated dissolution is idempotent');
    });

    test('a final delete failure rolls back both book and child updates',
        () async {
      await addGroup(6, parent: 5);
      await live.execute(
          "CREATE TRIGGER reject_dissolve BEFORE DELETE ON tb_groups WHEN OLD.id = 5 BEGIN SELECT RAISE(ABORT, 'blocked'); END");
      final before = await snapshot();
      await expectLater(
          container.read(groupDaoProvider.notifier).hardDeleteGroup(5),
          throwsA(isA<DatabaseException>()));
      expect(await snapshot(), before);
    });

    for (final id in [0, -1]) {
      test('root and invalid group $id are rejected without mutation',
          () async {
        final before = await snapshot();
        await expectLater(
            container.read(groupDaoProvider.notifier).hardDeleteGroup(id),
            throwsArgumentError);
        expect(await snapshot(), before);
      });
    }

    for (final invalidRoot in ['missing', 'deleted', 'parented']) {
      test('$invalidRoot root rejects dissolution without changing data',
          () async {
        if (invalidRoot == 'missing') {
          await live.delete('tb_groups', where: 'id = 0');
        } else {
          await live.update('tb_groups',
              invalidRoot == 'deleted' ? {'is_deleted': 1} : {'parent_id': 5},
              where: 'id = 0');
        }
        final before = await snapshot();
        await expectLater(
            container.read(groupDaoProvider.notifier).hardDeleteGroup(5),
            throwsStateError);
        expect(await snapshot(), before);
      });
    }

    test('empty or mixed provider input never deletes a folder', () async {
      final notifier = container.read(bookListProvider.notifier);
      final before = await snapshot();
      await Future<void>.sync(() => notifier.dissolveGroup([]));
      await expectLater(
          Future<void>.sync(() => notifier.dissolveGroup([
                Book.fromDb(book(11, 'member', groupId: 5)),
                Book.fromDb(book(1, 'root')),
              ])),
          throwsArgumentError);
      expect(await snapshot(), before);
    });
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
