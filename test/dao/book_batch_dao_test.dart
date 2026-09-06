import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
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
              reading_status INTEGER DEFAULT 0,
              start_reading_time TEXT,
              finish_reading_time TEXT,
              read_count INTEGER DEFAULT 0
            )
          ''');
        },
      ),
    );
    DBHelper.setDatabaseForTesting(db);
  });

  tearDown(() async {
    DBHelper.setDatabaseForTesting(null);
    await db.close();
  });

  group('BookDao Batch Operations Specification (TDD)', () {
    test('Scenario: Batch update reading status to finished updates timestamps and readCount', () async {
      final now = DateTime.now();
      final book1 = Book(
        id: -1,
        title: 'Book 1',
        coverPath: 'c1.png',
        filePath: 'b1.epub',
        lastReadPosition: '',
        readingPercentage: 0.2,
        author: 'Author 1',
        isDeleted: false,
        rating: 0,
        status: ReadingStatus.reading,
        createTime: now,
        updateTime: now,
      );
      final book2 = Book(
        id: -1,
        title: 'Book 2',
        coverPath: 'c2.png',
        filePath: 'b2.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author 2',
        isDeleted: false,
        rating: 0,
        status: ReadingStatus.unread,
        createTime: now,
        updateTime: now,
      );

      final id1 = await bookDao.insertBook(book1);
      final id2 = await bookDao.insertBook(book2);

      // Batch update status to finished
      await bookDao.batchUpdateStatus([id1, id2], ReadingStatus.finished);

      final updated1 = await bookDao.selectBookById(id1);
      final updated2 = await bookDao.selectBookById(id2);

      expect(updated1.status, ReadingStatus.finished);
      expect(updated1.finishReadingTime, isNotNull);
      expect(updated1.readCount, 1);

      expect(updated2.status, ReadingStatus.finished);
      expect(updated2.finishReadingTime, isNotNull);
      expect(updated2.readCount, 1);
    });

    test('Scenario: Batch update group updates group_id for all specified books', () async {
      final now = DateTime.now();
      final id1 = await bookDao.insertBook(Book(
        id: -1,
        title: 'Book 1',
        coverPath: '',
        filePath: '',
        lastReadPosition: '',
        readingPercentage: 0,
        author: '',
        isDeleted: false,
        rating: 0,
        groupId: 0,
        createTime: now,
        updateTime: now,
      ));
      final id2 = await bookDao.insertBook(Book(
        id: -1,
        title: 'Book 2',
        coverPath: '',
        filePath: '',
        lastReadPosition: '',
        readingPercentage: 0,
        author: '',
        isDeleted: false,
        rating: 0,
        groupId: 0,
        createTime: now,
        updateTime: now,
      ));

      await bookDao.batchUpdateGroup([id1, id2], 42);

      final updated1 = await bookDao.selectBookById(id1);
      final updated2 = await bookDao.selectBookById(id2);

      expect(updated1.groupId, 42);
      expect(updated2.groupId, 42);
    });

    test('Scenario: Batch soft-delete sets is_deleted = 1 while preserving book record in database', () async {
      final now = DateTime.now();
      final id1 = await bookDao.insertBook(Book(
        id: -1,
        title: 'Delete Book 1',
        coverPath: '',
        filePath: '',
        lastReadPosition: '',
        readingPercentage: 0.5,
        author: '',
        isDeleted: false,
        rating: 4,
        createTime: now,
        updateTime: now,
      ));
      final id2 = await bookDao.insertBook(Book(
        id: -1,
        title: 'Delete Book 2',
        coverPath: '',
        filePath: '',
        lastReadPosition: '',
        readingPercentage: 0.9,
        author: '',
        isDeleted: false,
        rating: 5,
        createTime: now,
        updateTime: now,
      ));

      await bookDao.batchSoftDelete([id1, id2]);

      final activeBooks = await bookDao.selectNotDeleteBooks();
      expect(activeBooks.any((b) => b.id == id1 || b.id == id2), isFalse);

      final book1All = await bookDao.selectBookById(id1);
      final book2All = await bookDao.selectBookById(id2);
      expect(book1All.isDeleted, isTrue);
      expect(book2All.isDeleted, isTrue);
    });
  });
}
