import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/models/book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notes_statistics.g.dart';

@riverpod
class NotesStatistics extends _$NotesStatistics {
  @override
  Future<Map<String, int>> build() async {
    return _getNotesStatistics();
  }

  Future<Map<String, int>> _getNotesStatistics() async {
    return await bookNoteDao.selectNumberOfNotesAndBooks();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _getNotesStatistics());
  }
}

@riverpod
class BookIdAndNotes extends _$BookIdAndNotes {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final bookDataList = await bookNoteDao.selectAllBookIdAndNotes();
    if (bookDataList.isEmpty) return [];

    final bookIds =
        bookDataList.map((data) => data['bookId'] as int).toList();
    final booksFuture = bookDao.selectBooksByIds(bookIds);
    final readingTimesFuture =
        readingTimeDao.selectTotalReadingTimesByBookIds(bookIds);

    final results = await Future.wait([booksFuture, readingTimesFuture]);
    final books = {for (final book in results[0] as List<Book>) book.id: book};
    final readingTimes = results[1] as Map<int, int>;

    return bookDataList.map((data) {
      final bookId = data['bookId'] as int;
      final book = books[bookId];
      if (book == null) {
        return null;
      }
      return <String, dynamic>{
        'bookId': bookId,
        'numberOfNotes': data['numberOfNotes'],
        'latestTime': data['latestTime'],
        'book': book,
        'readingTime': readingTimes[bookId] ?? 0,
      };
    }).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await build());
  }
}

@riverpod
class BookReadingTime extends _$BookReadingTime {
  @override
  Future<int> build(int bookId) async {
    return _getBookReadingTime(bookId);
  }

  Future<int> _getBookReadingTime(int bookId) async {
    return await readingTimeDao.selectTotalReadingTimeByBookId(bookId);
  }

  Future<void> refresh(int bookId) async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _getBookReadingTime(bookId));
  }
}
