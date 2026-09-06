import 'package:anx_reader/page/reading_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadingPageKeyAccessor & Lifecycle Contract Tests', () {
    test('GIVEN no active reader, WHEN accessor is checked, THEN returns null', () {
      expect(ReadingPageState.activeState, isNull);
      expect(readingPageKey.currentState, isNull);
      expect(readingPageKey.currentContext, isNull);
      expect(readingPageKey.currentWidget, isNull);
      expect(epubPlayerKey.currentState, isNull);
      expect(epubPlayerKey.currentContext, isNull);
      expect(epubPlayerKey.currentWidget, isNull);
    });

    test('GIVEN multiple readers mounted, WHEN checked, THEN tracks top of stack and falls back cleanly', () {
      // Simulate state instances
      final state1 = ReadingPageState();
      final state2 = ReadingPageState();

      // Mount state1
      ReadingPageState.activeStatesForTesting.add(state1);
      expect(ReadingPageState.activeState, equals(state1));
      expect(readingPageKey.currentState, equals(state1));

      // Mount state2 on top (e.g. preview or transition)
      ReadingPageState.activeStatesForTesting.add(state2);
      expect(ReadingPageState.activeState, equals(state2));
      expect(readingPageKey.currentState, equals(state2));

      // Pop state2
      ReadingPageState.activeStatesForTesting.remove(state2);
      expect(ReadingPageState.activeState, equals(state1));
      expect(readingPageKey.currentState, equals(state1));

      // Pop state1
      ReadingPageState.activeStatesForTesting.remove(state1);
      expect(ReadingPageState.activeState, isNull);
      expect(readingPageKey.currentState, isNull);
    });
  });
}
