import 'package:anx_reader/providers/bookshelf_selection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookshelfSelectionNotifier State Specification (TDD)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Scenario: Initial state is not in selection mode with empty set', () {
      final state = container.read(bookshelfSelectionNotifierProvider);
      expect(state.isSelectionMode, isFalse);
      expect(state.selectedBookIds, isEmpty);
      expect(state.selectedCount, 0);
    });

    test('Scenario: Enter selection mode with optional initial book ID', () {
      final notifier = container.read(bookshelfSelectionNotifierProvider.notifier);
      notifier.enterSelectionMode(42);

      final state = container.read(bookshelfSelectionNotifierProvider);
      expect(state.isSelectionMode, isTrue);
      expect(state.selectedBookIds, contains(42));
      expect(state.selectedCount, 1);
      expect(state.isSelected(42), isTrue);
      expect(state.isSelected(99), isFalse);
    });

    test('Scenario: Toggle selection on and off', () {
      final notifier = container.read(bookshelfSelectionNotifierProvider.notifier);
      notifier.enterSelectionMode();

      notifier.toggle(10);
      expect(container.read(bookshelfSelectionNotifierProvider).isSelected(10), isTrue);

      notifier.toggle(20);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedCount, 2);

      notifier.toggle(10);
      expect(container.read(bookshelfSelectionNotifierProvider).isSelected(10), isFalse);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedCount, 1);
    });

    test('Scenario: Scoped selectAll and deselectAll', () {
      final notifier = container.read(bookshelfSelectionNotifierProvider.notifier);
      notifier.enterSelectionMode();

      notifier.selectAll([1, 2, 3]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedCount, 3);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedBookIds, {1, 2, 3});

      notifier.deselectAll();
      expect(container.read(bookshelfSelectionNotifierProvider).selectedCount, 0);
      expect(container.read(bookshelfSelectionNotifierProvider).isSelectionMode, isTrue);
    });

    test('Scenario: Exit selection mode clears selection and resets flag', () {
      final notifier = container.read(bookshelfSelectionNotifierProvider.notifier);
      notifier.enterSelectionMode(1);
      notifier.toggle(2);
      notifier.exitSelectionMode();
      final state = container.read(bookshelfSelectionNotifierProvider);
      expect(state.isSelectionMode, isFalse);
      expect(state.selectedBookIds, isEmpty);
    });

    test('Scenario: toggleFolder adds all if some/none selected, and removes all if all selected', () {
      final notifier = container.read(bookshelfSelectionNotifierProvider.notifier);
      notifier.enterSelectionMode();

      // Empty folder does nothing
      notifier.toggleFolder([]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedCount, 0);

      // Folder with books [101, 102]: none selected -> select all in folder
      notifier.toggleFolder([101, 102]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedBookIds, {101, 102});

      // Partially selected: 101 selected, 103 not selected -> select all in folder
      notifier.toggle(102); // now only 101 is selected
      notifier.toggleFolder([101, 103]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedBookIds, {101, 103});

      // All in folder selected -> deselect all in folder
      notifier.toggleFolder([101, 103]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedBookIds, isEmpty);
    });

    test('Scenario: toggleAll selects all visible books if not all selected, or deselects all if all selected', () {
      final notifier = container.read(bookshelfSelectionNotifierProvider.notifier);
      notifier.enterSelectionMode();

      // Empty visible list does nothing
      notifier.toggleAll([]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedCount, 0);

      // Not all selected -> select all
      notifier.toggleAll([1, 2, 3]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedBookIds, {1, 2, 3});

      // All selected -> deselect all
      notifier.toggleAll([1, 2, 3]);
      expect(container.read(bookshelfSelectionNotifierProvider).selectedBookIds, isEmpty);
    });
  });
}
