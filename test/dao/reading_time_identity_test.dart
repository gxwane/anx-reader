import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadingTimeDao dao;

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
        onCreate: (db, version) async {
          await db.execute(createReadingTimeSQL);
          await db.execute(createReadingTimeIdentityIndexSQL);
        },
      ),
    );
    DBHelper.setDatabaseForTesting(db);
    dao = ReadingTimeDao();
  });

  tearDown(() async {
    DBHelper.setDatabaseForTesting(null);
    await db.close();
  });

  test('normalizes a legacy timestamp and accumulates plain seconds', () async {
    await db.insert('tb_reading_time', {
      'id': 1,
      'book_id': 7,
      'date': '2026-09-16T08:30:00.000',
      'reading_time': 60,
    });

    await dao.insertReadingTime(
      ReadingTime(
        bookId: 7,
        date: '2026-09-16T20:45:00.000',
        readingTime: 5,
      ),
    );

    final rows = await db.query('tb_reading_time');
    expect(rows, hasLength(1));
    expect(rows.single['date'], '2026-09-16');
    expect(rows.single['reading_time'], 65);
  });

  test('same book on a different day creates a separate row', () async {
    await dao.insertReadingSession(
        bookId: 7, readingTime: 10, startedAt: DateTime(2026, 9, 16, 8));
    await dao.insertReadingSession(
        bookId: 7, readingTime: 20, startedAt: DateTime(2026, 9, 17, 8));

    final rows = await db.query('tb_reading_time', orderBy: 'date');
    expect(rows.map((row) => row['date']), ['2026-09-16', '2026-09-17']);
    expect(rows.map((row) => row['reading_time']), [10, 20]);
  });

  test('rejects negative durations without changing stored totals', () async {
    await dao.insertReadingSession(
        bookId: 7, readingTime: 10, startedAt: DateTime(2026, 9, 16));

    await expectLater(
      dao.insertReadingSession(
          bookId: 7, readingTime: -1, startedAt: DateTime(2026, 9, 16)),
      throwsArgumentError,
    );

    expect((await db.query('tb_reading_time')).single['reading_time'], 10);
  });
}
