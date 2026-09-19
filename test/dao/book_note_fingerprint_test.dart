import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late BookNoteDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onCreate: (db, version) async {
          await db.execute(createNoteSQL);
          await db.execute(createNoteIdentityIndexSQL);
        },
        version: 1,
      ),
    );
    DBHelper.setDatabaseForTesting(db);
    dao = BookNoteDao();
  });

  tearDown(() async {
    DBHelper.setDatabaseForTesting(null);
    await db.close();
  });

  Future<void> insertNote({
    required int id,
    required int bookId,
    required String cfi,
    required String content,
  }) {
    return db.insert('tb_notes', {
      'id': id,
      'book_id': bookId,
      'content': content,
      'cfi': cfi,
      'chapter': 'chapter',
      'type': 'highlight',
      'color': 'FFD700',
      'create_time': '2026-09-01T00:00:00.000Z',
      'update_time': '2026-09-01T00:00:00.000Z',
    }).then((_) {});
  }

  Future<List<Map<String, Object?>>> snapshot() =>
      db.query('tb_notes', orderBy: 'id');

  Map<String, Object?> move(int id, String oldCfi, String newCfi,
          {String? prefix, String? suffix}) =>
      {
        'id': id,
        'oldCfi': oldCfi,
        'newCfi': newCfi,
        if (prefix != null) 'prefix': prefix,
        if (suffix != null) 'suffix': suffix,
      };

  group('BookNote context fingerprint', () {
    test('serializes and deserializes context around the annotation', () {
      final now = DateTime.utc(2026, 9, 3, 12);
      final note = BookNote(
        id: 42,
        bookId: 101,
        content: 'thesis statement',
        cfi: 'old',
        chapter: 'Chapter 1',
        type: 'highlight',
        color: 'FFD700',
        readerNote: 'Personal thought',
        contextPrefix: 'context before ',
        contextSuffix: ' context after',
        createTime: now,
        updateTime: now,
      );

      final reconstructed = BookNote.fromDb(note.toMap());
      expect(reconstructed.id, 42);
      expect(reconstructed.contextPrefix, 'context before ');
      expect(reconstructed.contextSuffix, ' context after');
      expect(note.toJson()['contextPrefix'], 'context before ');
      expect(note.toJson()['contextSuffix'], ' context after');
    });

    test('save updates the unique identity in place regardless of note type',
        () async {
      await insertNote(id: 5, bookId: 7, cfi: 'same', content: 'old');
      await db.update('tb_notes', {'type': 'book-review'},
          where: 'id = 5');
      final now = DateTime.utc(2026, 9, 16);

      final id = await dao.save(BookNote(
        bookId: 7,
        content: 'new',
        cfi: 'same',
        chapter: 'chapter',
        type: 'highlight',
        color: 'FFD700',
        updateTime: now,
      ));

      expect(id, 5);
      final rows = await snapshot();
      expect(rows, hasLength(1));
      expect(rows.single['id'], 5);
      expect(rows.single['content'], 'new');
    });

    test('save rejects an empty identity', () async {
      final now = DateTime.utc(2026, 9, 16);
      await expectLater(
        dao.save(BookNote(
          bookId: 7,
          content: 'new',
          cfi: '   ',
          chapter: 'chapter',
          type: 'highlight',
          color: 'FFD700',
          updateTime: now,
        )),
        throwsArgumentError,
      );
      expect(await snapshot(), isEmpty);
    });
  });

  group('Atomic CFI relocation', () {
    test('moves and refreshes context while retaining ID and content', () async {
      await insertNote(id: 1, bookId: 7, cfi: 'old', content: 'keep me');

      final result = await dao.relocateCfis(7, [
        move(1, 'old', 'new', prefix: 'before', suffix: 'after'),
      ]);

      expect(result.isSuccess, isTrue);
      expect(result.updatedCount, 1);
      final row = (await snapshot()).single;
      expect(row['id'], 1);
      expect(row['content'], 'keep me');
      expect(row['cfi'], 'new');
      expect(row['context_prefix'], 'before');
      expect(row['context_suffix'], 'after');
    });

    test('allows an in-place context refresh', () async {
      await insertNote(id: 1, bookId: 7, cfi: 'same', content: 'keep me');

      final result = await dao.relocateCfis(7, [
        move(1, 'same', 'same', prefix: 'new context'),
      ]);

      expect(result.isSuccess, isTrue);
      expect((await snapshot()).single['context_prefix'], 'new context');
    });

    Future<void> expectRejected(
      List<Map<String, Object?>> commands,
      BookNoteRelocationFailure failure,
    ) async {
      final before = await snapshot();
      final result = await dao.relocateCfis(7, commands);
      expect(result.isSuccess, isFalse);
      expect(result.failure, failure);
      expect(await snapshot(), before);
    }

    test('rejects a target occupied by a record outside the batch', () async {
      await insertNote(id: 1, bookId: 7, cfi: 'one', content: 'first');
      await insertNote(id: 2, bookId: 7, cfi: 'two', content: 'second');
      await expectRejected(
        [move(1, 'one', 'two')],
        BookNoteRelocationFailure.occupiedTarget,
      );
    });

    test('rejects swaps and occupied chains even when occupants also move',
        () async {
      await insertNote(id: 1, bookId: 7, cfi: 'one', content: 'first');
      await insertNote(id: 2, bookId: 7, cfi: 'two', content: 'second');
      await expectRejected(
        [move(1, 'one', 'two'), move(2, 'two', 'one')],
        BookNoteRelocationFailure.occupiedTarget,
      );
    });

    test('rejects different records targeting the same CFI', () async {
      await insertNote(id: 1, bookId: 7, cfi: 'one', content: 'first');
      await insertNote(id: 2, bookId: 7, cfi: 'two', content: 'second');
      await expectRejected(
        [move(1, 'one', 'new'), move(2, 'two', 'new')],
        BookNoteRelocationFailure.duplicateTarget,
      );
    });

    test('rejects contradictory instructions for one record', () async {
      await insertNote(id: 1, bookId: 7, cfi: 'one', content: 'first');
      await expectRejected(
        [move(1, 'one', 'new-a'), move(1, 'one', 'new-b')],
        BookNoteRelocationFailure.conflictingInstruction,
      );
    });

    test('rejects missing, cross-book, stale and malformed commands',
        () async {
      await insertNote(id: 1, bookId: 7, cfi: 'one', content: 'first');
      await insertNote(id: 2, bookId: 8, cfi: 'other', content: 'other book');

      await expectRejected(
        [move(99, 'missing', 'new')],
        BookNoteRelocationFailure.missingNote,
      );
      await expectRejected(
        [move(2, 'other', 'new')],
        BookNoteRelocationFailure.wrongBook,
      );
      await expectRejected(
        [move(1, 'stale', 'new')],
        BookNoteRelocationFailure.staleSource,
      );
      await expectRejected(
        [move(1, 'one', '')],
        BookNoteRelocationFailure.invalidInput,
      );
    });

    test('rolls back earlier updates when a later SQL update fails', () async {
      await insertNote(id: 1, bookId: 7, cfi: 'one', content: 'first');
      await insertNote(id: 2, bookId: 7, cfi: 'two', content: 'second');
      await db.execute('''
        CREATE TRIGGER reject_second_relocation
        BEFORE UPDATE ON tb_notes
        WHEN OLD.id = 2
        BEGIN SELECT RAISE(ABORT, 'blocked'); END
      ''');
      final before = await snapshot();

      final result = await dao.relocateCfis(7, [
        move(1, 'one', 'new-one'),
        move(2, 'two', 'new-two'),
      ]);

      expect(result.isSuccess, isFalse);
      expect(result.failure, BookNoteRelocationFailure.databaseFailure);
      expect(await snapshot(), before);
    });
  });
}
