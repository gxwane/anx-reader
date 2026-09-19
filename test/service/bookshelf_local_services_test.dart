import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan_book.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan_group.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_batch_service.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_organize_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  Future<void> createSchema(Database db) async {
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
    await db.execute(createGroupSQL);
    await db.execute(createNoteSQL);
    await db.execute(createReadingTimeSQL);
    await db.execute(createNoteIdentityIndexSQL);
    await db.execute(createReadingTimeIdentityIndexSQL);
    await db.insert('tb_groups', {
      'id': 0,
      'name': 'Root',
      'parent_id': null,
      'is_deleted': 0,
    });
  }

  Book makeBook(int id, {int groupId = 0}) {
    final now = DateTime.utc(2026, 9, 16);
    return Book(
      id: id,
      title: 'Book $id',
      coverPath: '',
      filePath: '',
      lastReadPosition: 'cfi-$id',
      readingPercentage: 0.4,
      author: 'author',
      isDeleted: false,
      rating: 0,
      groupId: groupId,
      status: ReadingStatus.reading,
      createTime: now,
      updateTime: now,
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 1,
        onCreate: (db, version) => createSchema(db),
      ),
    );
    DBHelper.setDatabaseForTesting(db);
    await db.insert('tb_books', makeBook(1).toMap());
  });

  tearDown(() async {
    DBHelper.setDatabaseForTesting(null);
    await db.close();
  });

  test('organize service applies local groups without Provider dependencies',
      () async {
    const member = BookshelfOrganizePlanBook(bookId: 1, title: 'Book 1');
    await BookshelfOrganizeService().applyPlan(
      const BookshelfOrganizePlan(
        groups: [
          BookshelfOrganizePlanGroup(
            groupId: 7,
            createNew: true,
            proposedName: '  Science  ',
            books: [member],
          ),
        ],
      ),
    );

    final group = (await db.query('tb_groups', where: 'id = 7')).single;
    expect(group['name'], 'Science');
    expect(group['parent_id'], 0);
    expect((await db.query('tb_books')).single['group_id'], 7);

    await BookshelfOrganizeService().applyPlan(
      const BookshelfOrganizePlan(
        ungroupedBooks: [member],
        cleanupGroupIds: [7],
      ),
    );
    expect((await db.query('tb_books')).single['group_id'], 0);
    expect((await db.query('tb_groups', where: 'id = 7')).single['is_deleted'],
        1);
  });

  test('missing organize book is rejected before group creation', () async {
    await expectLater(
      BookshelfOrganizeService().applyPlan(
        const BookshelfOrganizePlan(
          groups: [
            BookshelfOrganizePlanGroup(
              groupId: 7,
              createNew: true,
              books: [
                BookshelfOrganizePlanBook(bookId: 99, title: 'missing'),
              ],
            ),
          ],
        ),
      ),
      throwsStateError,
    );
    expect(await db.query('tb_groups', where: 'id = 7'), isEmpty);
  });

  test('batch removal retains note and reading statistics', () async {
    await db.insert('tb_notes', {
      'book_id': 1,
      'cfi': 'note',
      'content': 'personal knowledge',
    });
    await db.insert('tb_reading_time', {
      'book_id': 1,
      'date': '2026-09-16',
      'reading_time': 42,
    });

    await BookshelfBatchService().batchDeleteBooks([makeBook(1)]);

    expect((await db.query('tb_books')).single['is_deleted'], 1);
    expect((await db.query('tb_notes')).single['content'], 'personal knowledge');
    expect((await db.query('tb_reading_time')).single['reading_time'], 42);
  });
}
