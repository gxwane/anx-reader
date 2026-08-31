import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadingStatus Enum & Book Model Specification', () {
    test('ReadingStatus enum should have 4 core statuses with correct values', () {
      expect(ReadingStatus.unread.value, 0);
      expect(ReadingStatus.reading.value, 1);
      expect(ReadingStatus.finished.value, 2);
      expect(ReadingStatus.abandoned.value, 3);
    });

    test('ReadingStatus.fromValue resolves valid and fallback values (Mutant M1)', () {
      expect(ReadingStatus.fromValue(0), ReadingStatus.unread);
      expect(ReadingStatus.fromValue(1), ReadingStatus.reading);
      expect(ReadingStatus.fromValue(2), ReadingStatus.finished);
      expect(ReadingStatus.fromValue(3), ReadingStatus.abandoned);
      // Boundary/fallback check: unknown values must safely fallback to unread
      expect(ReadingStatus.fromValue(-1), ReadingStatus.unread);
      expect(ReadingStatus.fromValue(999), ReadingStatus.unread);
    });

    test('Book model default status is unread', () {
      final book = Book.mock();
      expect(book.status, ReadingStatus.unread);
      expect(book.readCount, 0);
      expect(book.startReadingTime, isNull);
      expect(book.finishReadingTime, isNull);
    });

    test('Book model fromDb gracefully parses new status fields', () {
      final now = DateTime.now();
      final map = {
        'id': 10,
        'title': 'Test Book',
        'cover_path': 'cover.png',
        'file_path': 'test.epub',
        'last_read_position': 'epubcfi(/6/2[chapter1]!/4/2)',
        'reading_percentage': 0.75,
        'author': 'Author',
        'is_deleted': 0,
        'description': 'Desc',
        'rating': 4.5,
        'group_id': 1,
        'file_md5': 'abc123',
        'create_time': now.toIso8601String(),
        'update_time': now.toIso8601String(),
        'reading_status': 2,
        'start_reading_time': now.subtract(const Duration(days: 5)).toIso8601String(),
        'finish_reading_time': now.toIso8601String(),
        'read_count': 1,
      };

      final book = Book.fromDb(map);
      expect(book.status, ReadingStatus.finished);
      expect(book.readCount, 1);
      expect(book.startReadingTime, isNotNull);
      expect(book.finishReadingTime, isNotNull);
      expect(book.readingPercentage, 0.75);
    });

    test('Book model fromDb handles legacy db records where status columns are null', () {
      final now = DateTime.now();
      final legacyMap = {
        'id': 11,
        'title': 'Legacy Book',
        'cover_path': 'cover.png',
        'file_path': 'test.epub',
        'last_read_position': 'pos',
        'reading_percentage': 0.5,
        'author': 'Author',
        'is_deleted': 0,
        'rating': 0.0,
        'create_time': now.toIso8601String(),
        'update_time': now.toIso8601String(),
        // New columns are absent / null in legacy records
        'reading_status': null,
        'start_reading_time': null,
        'finish_reading_time': null,
        'read_count': null,
      };

      final book = Book.fromDb(legacyMap);
      expect(book.status, ReadingStatus.unread);
      expect(book.readCount, 0);
      expect(book.startReadingTime, isNull);
      expect(book.finishReadingTime, isNull);
    });

    test('Book toMap correctly serializes status fields', () {
      final startTime = DateTime(2026, 1, 1, 10, 0);
      final finishTime = DateTime(2026, 1, 5, 18, 30);
      final now = DateTime.now();

      final book = Book(
        id: 1,
        title: 'Serialization Test',
        coverPath: 'c.png',
        filePath: 'f.epub',
        lastReadPosition: 'cfi',
        readingPercentage: 0.85,
        author: 'Author',
        isDeleted: false,
        rating: 5.0,
        status: ReadingStatus.finished,
        startReadingTime: startTime,
        finishReadingTime: finishTime,
        readCount: 2,
        createTime: now,
        updateTime: now,
      );

      final map = book.toMap();
      expect(map['reading_status'], 2);
      expect(map['start_reading_time'], startTime.toIso8601String());
      expect(map['finish_reading_time'], finishTime.toIso8601String());
      expect(map['read_count'], 2);
    });

    test('Book copyWith modifies status without modifying reading position (Mutant M3)', () {
      final now = DateTime.now();
      final book = Book(
        id: 1,
        title: 'Preserve Position',
        coverPath: 'c.png',
        filePath: 'f.epub',
        lastReadPosition: 'cfi_at_80_percent',
        readingPercentage: 0.80,
        author: 'Author',
        isDeleted: false,
        rating: 5.0,
        status: ReadingStatus.reading,
        createTime: now,
        updateTime: now,
      );

      final finishedBook = book.copyWith(
        status: ReadingStatus.finished,
        finishReadingTime: now,
        readCount: book.readCount + 1,
      );

      // Must preserve reading percentage and CFI position
      expect(finishedBook.status, ReadingStatus.finished);
      expect(finishedBook.readingPercentage, 0.80);
      expect(finishedBook.lastReadPosition, 'cfi_at_80_percent');
      expect(finishedBook.readCount, 1);
    });
  });
}
