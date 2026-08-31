import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book_filters.g.dart';

enum ReadingStatusFilter {
  none,
  reading,
  unread,
  finished,
  abandoned,
}

bool matchesReadingStatus(Book book, ReadingStatusFilter filter) {
  switch (filter) {
    case ReadingStatusFilter.none:
      return true;
    case ReadingStatusFilter.reading:
      return book.status == ReadingStatus.reading;
    case ReadingStatusFilter.unread:
      return book.status == ReadingStatus.unread;
    case ReadingStatusFilter.finished:
      return book.status == ReadingStatus.finished;
    case ReadingStatusFilter.abandoned:
      return book.status == ReadingStatus.abandoned;
  }
}

@riverpod
class ReadingStatusFilterNotifier extends _$ReadingStatusFilterNotifier {
  @override
  ReadingStatusFilter build() {
    final stored = Prefs().bookshelfReadingStatusFilter;
    if (stored == 'notStarted') return ReadingStatusFilter.unread;
    return ReadingStatusFilter.values.firstWhere(
      (status) => status.name == stored,
      orElse: () => ReadingStatusFilter.none,
    );
  }

  void toggle(ReadingStatusFilter status) {
    if (state == status) {
      state = ReadingStatusFilter.none;
    } else {
      state = status;
    }
    Prefs().bookshelfReadingStatusFilter = state.name;
  }

  void clear() {
    state = ReadingStatusFilter.none;
    Prefs().bookshelfReadingStatusFilter = state.name;
  }
}
