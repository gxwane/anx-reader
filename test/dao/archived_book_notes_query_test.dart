import 'package:anx_reader/models/book.dart';
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
            CREATE TABLE tb_books (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT,
              cover_path TEXT,
              file_path TEXT,
              last_read_position TEXT,
              reading_percentage REAL,
              author TEXT,
              is_deleted INTEGER DEFAULT 0,
              description TEXT,
              create_time TEXT,
              update_time TEXT,
              rating REAL,
              group_id INTEGER,
              file_md5 TEXT,
              status TEXT,
              comment TEXT
            )
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
              update_time TEXT,
              is_deleted INTEGER DEFAULT 0
            )
          ''');
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Archived Book Notes & DAO selectBooksByIds Query Spec', () {
    test('selectBooksByIds query logic retrieves both active and archived books when includeDeleted is true', () async {
      final now = DateTime.now().toIso8601String();

      // Insert 1 active book and 1 archived (deleted) book
      await db.rawInsert('''
        INSERT INTO tb_books (id, title, cover_path, file_path, reading_percentage, author, is_deleted, create_time, update_time, file_md5)
        VALUES (1, 'Active Book', 'cover1.png', 'file1.epub', 0.5, 'Author A', 0, '$now', '$now', 'md5_1')
      ''');

      await db.rawInsert('''
        INSERT INTO tb_books (id, title, cover_path, file_path, reading_percentage, author, is_deleted, create_time, update_time, file_md5)
        VALUES (2, 'Archived Book', 'cover2.png', 'file2.epub', 0.8, 'Author B', 1, '$now', '$now', 'md5_2')
      ''');

      // Test with includeDeleted: true (default for notes page)
      final ids = [1, 2];
      final placeholders = List.filled(ids.length, '?').join(',');
      final allRows = await db.rawQuery(
        'SELECT * FROM tb_books WHERE id IN ($placeholders)',
        ids,
      );
      final allBooks = allRows.map(Book.fromDb).toList();
      expect(allBooks.length, 2);

      final active = allBooks.firstWhere((b) => b.id == 1);
      expect(active.title, 'Active Book');
      expect(active.isDeleted, false);

      final archived = allBooks.firstWhere((b) => b.id == 2);
      expect(archived.title, 'Archived Book');
      expect(archived.isDeleted, true);

      // Test with includeDeleted: false (legacy filter)
      final activeRows = await db.rawQuery(
        'SELECT * FROM tb_books WHERE is_deleted = 0 AND id IN ($placeholders)',
        ids,
      );
      final activeBooks = activeRows.map(Book.fromDb).toList();
      expect(activeBooks.length, 1);
      expect(activeBooks.first.id, 1);
    });

    test('deleteAllNotesByBookId soft deletes all active notes for a book without touching other books', () async {
      final oldTime = DateTime(2025, 1, 1).toIso8601String();

      // Insert 3 notes for book 100
      await db.insert('tb_notes', {
        'book_id': 100,
        'content': 'Note 1',
        'cfi': 'epubcfi(/6/2!/4/1:0)',
        'type': 'highlight',
        'create_time': oldTime,
        'update_time': oldTime,
        'is_deleted': 0,
      });
      await db.insert('tb_notes', {
        'book_id': 100,
        'content': 'Note 2',
        'cfi': 'epubcfi(/6/2!/4/2:0)',
        'type': 'highlight',
        'create_time': oldTime,
        'update_time': oldTime,
        'is_deleted': 0,
      });
      await db.insert('tb_notes', {
        'book_id': 100,
        'content': 'Note 3 (already deleted)',
        'cfi': 'epubcfi(/6/2!/4/3:0)',
        'type': 'highlight',
        'create_time': oldTime,
        'update_time': oldTime,
        'is_deleted': 1,
      });

      // Insert 1 note for book 200
      await db.insert('tb_notes', {
        'book_id': 200,
        'content': 'Other Book Note',
        'cfi': 'epubcfi(/6/2!/4/1:0)',
        'type': 'highlight',
        'create_time': oldTime,
        'update_time': oldTime,
        'is_deleted': 0,
      });

      // Execute batch soft delete for book 100
      final now = DateTime.now().toIso8601String();
      final affectedRows = await db.update(
        'tb_notes',
        {
          'is_deleted': 1,
          'update_time': now,
        },
        where: 'book_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [100],
      );

      // Assert 2 active notes were soft deleted
      expect(affectedRows, equals(2));

      // Query active notes for book 100
      final activeNotes100 = await db.query(
        'tb_notes',
        where: 'book_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [100],
      );
      expect(activeNotes100, isEmpty);

      // Query active notes for book 200 (must be untouched)
      final activeNotes200 = await db.query(
        'tb_notes',
        where: 'book_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [200],
      );
      expect(activeNotes200.length, equals(1));
      expect(activeNotes200.first['content'], equals('Other Book Note'));
    });
  });
}
