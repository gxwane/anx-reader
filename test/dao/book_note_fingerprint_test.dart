import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/sync/record_merger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
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
              update_time TEXT,
              is_deleted INTEGER DEFAULT 0,
              context_prefix TEXT,
              context_suffix TEXT
            )
          ''');
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('BookNote Context Fingerprint Model Tests', () {
    test('serializes and deserializes contextPrefix and contextSuffix correctly', () {
      final now = DateTime.utc(2026, 9, 3, 12, 0, 0);
      final note = BookNote(
        id: 42,
        bookId: 101,
        content: 'thesis statement',
        cfi: 'epubcfi(/6/4!/4/2/1:0)',
        chapter: 'Chapter 1',
        type: 'highlight',
        color: 'FFD700',
        readerNote: 'Personal thought',
        contextPrefix: 'context before ',
        contextSuffix: ' context after',
        createTime: now,
        updateTime: now,
        isDeleted: false,
      );

      final map = note.toMap();
      expect(map['context_prefix'], 'context before ');
      expect(map['context_suffix'], ' context after');

      final reconstructed = BookNote.fromDb(map);
      expect(reconstructed.id, 42);
      expect(reconstructed.bookId, 101);
      expect(reconstructed.content, 'thesis statement');
      expect(reconstructed.contextPrefix, 'context before ');
      expect(reconstructed.contextSuffix, ' context after');

      final json = note.toJson();
      expect(json['id'], 42);
      expect(json['note'], 'thesis statement');
      expect(json['value'], 'epubcfi(/6/4!/4/2/1:0)');
      expect(json['contextPrefix'], 'context before ');
      expect(json['contextSuffix'], ' context after');
    });

    test('handles null contextPrefix and contextSuffix safely (backward compatibility)', () {
      final now = DateTime.utc(2026, 9, 3, 12, 0, 0);
      final legacyMap = {
        'id': 1,
        'book_id': 10,
        'content': 'old highlight',
        'cfi': 'epubcfi(/6/2!/4:0)',
        'chapter': 'Intro',
        'type': 'highlight',
        'color': 'FF0000',
        'reader_note': null,
        'is_deleted': 0,
        'create_time': now.toIso8601String(),
        'update_time': now.toIso8601String(),
      };

      final note = BookNote.fromDb(legacyMap);
      expect(note.contextPrefix, isNull);
      expect(note.contextSuffix, isNull);

      final json = note.toJson();
      expect(json['contextPrefix'], isNull);
      expect(json['contextSuffix'], isNull);
    });
  });

  group('Database Migration v9 -> v10 Spec', () {
    test('addColumnIfNotExists adds context_prefix and context_suffix idempotently', () async {
      final testDb = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 9,
          onCreate: (db, version) async {
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
                update_time TEXT,
                is_deleted INTEGER DEFAULT 0
              )
            ''');
          },
        ),
      );

      await testDb.insert('tb_notes', {
        'book_id': 1,
        'content': 'v9 note',
        'cfi': 'epubcfi(/6/2!/4:0)',
        'update_time': DateTime.now().toIso8601String(),
      });

      await DBHelper.addColumnIfNotExists(testDb, 'tb_notes', 'context_prefix', 'TEXT');
      await DBHelper.addColumnIfNotExists(testDb, 'tb_notes', 'context_suffix', 'TEXT');

      final columns = await testDb.rawQuery('PRAGMA table_info(tb_notes)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();

      expect(columnNames.contains('context_prefix'), isTrue);
      expect(columnNames.contains('context_suffix'), isTrue);

      final rows = await testDb.query('tb_notes');
      expect(rows.length, 1);
      expect(rows.first['content'], 'v9 note');
      expect(rows.first['context_prefix'], isNull);

      await testDb.close();
    });
  });

  group('Anti-Zombie Tombstone on Relocation Spec', () {
    test('batchUpdateCfiWithTombstones updates active note and creates tombstone for old CFI', () async {
      final initialTime = '2026-09-01T10:00:00.000Z';
      await db.insert('tb_notes', {
        'id': 100,
        'book_id': 55,
        'content': 'short phrase',
        'cfi': 'epubcfi(/6/2[old]!/4/1:0)',
        'chapter': 'Ch 1',
        'type': 'highlight',
        'color': 'FFD700',
        'is_deleted': 0,
        'create_time': initialTime,
        'update_time': initialTime,
      });

      final relocatedItems = [
        {
          'id': 100,
          'oldCfi': 'epubcfi(/6/2[old]!/4/1:0)',
          'newCfi': 'epubcfi(/6/4[repaired]!/4/2:10)',
          'prefix': 'leading words ',
          'suffix': ' trailing words',
        }
      ];

      final now = DateTime.now().toUtc().toIso8601String();
      await db.transaction((txn) async {
        for (final item in relocatedItems) {
          final id = item['id'] as int;
          final oldCfi = item['oldCfi'] as String;
          final newCfi = item['newCfi'] as String;
          final prefix = item['prefix'] as String?;
          final suffix = item['suffix'] as String?;

          final originalRows = await txn.query('tb_notes', where: 'id = ?', whereArgs: [id]);
          final original = originalRows.first;

          await txn.update(
            'tb_notes',
            {
              'cfi': newCfi,
              if (prefix != null) 'context_prefix': prefix,
              if (suffix != null) 'context_suffix': suffix,
              'update_time': now,
            },
            where: 'id = ?',
            whereArgs: [id],
          );

          if (oldCfi.isNotEmpty && oldCfi != newCfi) {
            await txn.insert('tb_notes', {
              'book_id': original['book_id'],
              'content': original['content'],
              'cfi': oldCfi,
              'chapter': original['chapter'],
              'type': original['type'],
              'color': original['color'],
              'is_deleted': 1,
              'create_time': original['create_time'],
              'update_time': now,
            });
          }
        }
      });

      final activeNotes = await db.query(
        'tb_notes',
        where: 'id = ?',
        whereArgs: [100],
      );
      expect(activeNotes.first['cfi'], 'epubcfi(/6/4[repaired]!/4/2:10)');
      expect(activeNotes.first['context_prefix'], 'leading words ');
      expect(activeNotes.first['is_deleted'], 0);

      final tombstones = await db.query(
        'tb_notes',
        where: 'cfi = ?',
        whereArgs: ['epubcfi(/6/2[old]!/4/1:0)'],
      );
      expect(tombstones.length, 1);
      expect(tombstones.first['is_deleted'], 1);

      final localAllNotes = await db.query('tb_notes');
      final localNotesWithMd5 = localAllNotes.map((n) => {
        ...n,
        'file_md5': 'test_md5_hash',
      }).toList();

      final remoteNotes = [
        {
          'book_id': 55,
          'file_md5': 'test_md5_hash',
          'content': 'short phrase',
          'cfi': 'epubcfi(/6/2[old]!/4/1:0)',
          'chapter': 'Ch 1',
          'type': 'highlight',
          'color': 'FFD700',
          'is_deleted': 0,
          'create_time': initialTime,
          'update_time': initialTime,
        }
      ];

      final merged = RecordMerger.mergeNotes(
        localNotes: localNotesWithMd5,
        remoteNotes: remoteNotes,
        md5ToLocalBookId: {'test_md5_hash': 55},
      );

      final oldCfiMerged = merged.firstWhere(
        (n) => n['cfi'] == 'epubcfi(/6/2[old]!/4/1:0)',
      );
      expect(oldCfiMerged['is_deleted'], 1, reason: 'Remote oldCfi must be marked deleted by local tombstone');

      final newCfiMerged = merged.firstWhere(
        (n) => n['cfi'] == 'epubcfi(/6/4[repaired]!/4/2:10)',
      );
      expect(newCfiMerged['is_deleted'], 0, reason: 'Repaired newCfi must be preserved as active');
    });
  });
}
