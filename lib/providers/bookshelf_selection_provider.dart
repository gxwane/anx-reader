import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bookshelf_selection_provider.g.dart';

class BookshelfSelectionState {
  final bool isSelectionMode;
  final Set<int> selectedBookIds;

  const BookshelfSelectionState({
    this.isSelectionMode = false,
    this.selectedBookIds = const {},
  });

  int get selectedCount => selectedBookIds.length;
  bool get isEmpty => selectedBookIds.isEmpty;
  bool isSelected(int id) => selectedBookIds.contains(id);

  BookshelfSelectionState copyWith({
    bool? isSelectionMode,
    Set<int>? selectedBookIds,
  }) {
    return BookshelfSelectionState(
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedBookIds: selectedBookIds ?? this.selectedBookIds,
    );
  }
}

@riverpod
class BookshelfSelectionNotifier extends _$BookshelfSelectionNotifier {
  @override
  BookshelfSelectionState build() {
    return const BookshelfSelectionState();
  }

  void enterSelectionMode([int? initialBookId]) {
    state = BookshelfSelectionState(
      isSelectionMode: true,
      selectedBookIds: initialBookId != null ? {initialBookId} : const {},
    );
  }

  void exitSelectionMode() {
    state = const BookshelfSelectionState(
      isSelectionMode: false,
      selectedBookIds: {},
    );
  }

  void toggle(int bookId) {
    final next = Set<int>.from(state.selectedBookIds);
    if (next.contains(bookId)) {
      next.remove(bookId);
    } else {
      next.add(bookId);
    }
    state = state.copyWith(selectedBookIds: next);
  }

  void toggleFolder(List<int> bookIdsInFolder) {
    if (bookIdsInFolder.isEmpty) return;
    final next = Set<int>.from(state.selectedBookIds);
    final allInFolderSelected = bookIdsInFolder.every(next.contains);
    if (allInFolderSelected) {
      next.removeAll(bookIdsInFolder);
    } else {
      next.addAll(bookIdsInFolder);
    }
    state = state.copyWith(selectedBookIds: next);
  }

  void selectAll(List<int> visibleBookIds) {
    final next = Set<int>.from(state.selectedBookIds)..addAll(visibleBookIds);
    state = state.copyWith(selectedBookIds: next);
  }

  void deselectAll() {
    state = state.copyWith(selectedBookIds: const {});
  }

  void toggleAll(List<int> visibleBookIds) {
    if (visibleBookIds.isEmpty) return;
    final allSelected = visibleBookIds.every(state.selectedBookIds.contains);
    if (allSelected) {
      deselectAll();
    } else {
      selectAll(visibleBookIds);
    }
  }
}

final bookshelfSelectionProvider = bookshelfSelectionNotifierProvider;
