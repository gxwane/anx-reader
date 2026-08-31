import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadingStatusFilter & Matching Logic Specification', () {
    final now = DateTime.now();

    final unreadBook = Book(
      id: 1,
      title: 'Unread Book',
      coverPath: '',
      filePath: '',
      lastReadPosition: '',
      readingPercentage: 0.0,
      author: 'Author A',
      isDeleted: false,
      rating: 0,
      status: ReadingStatus.unread,
      createTime: now,
      updateTime: now,
    );

    final readingBook = Book(
      id: 2,
      title: 'Reading Book',
      coverPath: '',
      filePath: '',
      lastReadPosition: 'pos',
      readingPercentage: 0.45,
      author: 'Author B',
      isDeleted: false,
      rating: 0,
      status: ReadingStatus.reading,
      createTime: now,
      updateTime: now,
    );

    final finishedBook = Book(
      id: 3,
      title: 'Finished Book',
      coverPath: '',
      filePath: '',
      lastReadPosition: 'pos',
      readingPercentage: 0.80, // Note: finished by explicit status, not percentage!
      author: 'Author C',
      isDeleted: false,
      rating: 5,
      status: ReadingStatus.finished,
      createTime: now,
      updateTime: now,
    );

    final abandonedBook = Book(
      id: 4,
      title: 'Abandoned Book',
      coverPath: '',
      filePath: '',
      lastReadPosition: 'pos',
      readingPercentage: 0.25,
      author: 'Author D',
      isDeleted: false,
      rating: 2,
      status: ReadingStatus.abandoned,
      createTime: now,
      updateTime: now,
    );

    final books = [unreadBook, readingBook, finishedBook, abandonedBook];

    test('ReadingStatusFilter matches each status correctly', () {
      bool matches(Book book, ReadingStatusFilter filter) {
        return matchesReadingStatus(book, filter);
      }

      // Filter: all / none
      expect(books.where((b) => matches(b, ReadingStatusFilter.none)).length, 4);

      // Filter: unread
      final unreadMatches = books.where((b) => matches(b, ReadingStatusFilter.unread)).toList();
      expect(unreadMatches.map((b) => b.id), [1]);

      // Filter: reading
      final readingMatches = books.where((b) => matches(b, ReadingStatusFilter.reading)).toList();
      expect(readingMatches.map((b) => b.id), [2]);

      // Filter: finished
      final finishedMatches = books.where((b) => matches(b, ReadingStatusFilter.finished)).toList();
      expect(finishedMatches.map((b) => b.id), [3]);

      // Filter: abandoned
      final abandonedMatches = books.where((b) => matches(b, ReadingStatusFilter.abandoned)).toList();
      expect(abandonedMatches.map((b) => b.id), [4]);
    });

    test('Mutant M2: Logic inversion in status filter is detected', () {
      // Ensure specific filter only returns the matching item and rejects non-matching items
      for (final book in books) {
        expect(matchesReadingStatus(book, ReadingStatusFilter.unread), book.status == ReadingStatus.unread);
        expect(matchesReadingStatus(book, ReadingStatusFilter.reading), book.status == ReadingStatus.reading);
        expect(matchesReadingStatus(book, ReadingStatusFilter.finished), book.status == ReadingStatus.finished);
        expect(matchesReadingStatus(book, ReadingStatusFilter.abandoned), book.status == ReadingStatus.abandoned);
      }
    });
  });
}
