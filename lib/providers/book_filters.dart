import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book_filters.g.dart';

enum ReadingStatusFilter { none, finished, reading, notStarted }

@riverpod
class ReadingStatusFilterNotifier extends _$ReadingStatusFilterNotifier {
  @override
  ReadingStatusFilter build() {
    final stored = Prefs().bookshelfReadingStatusFilter;
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
