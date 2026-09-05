import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test contract helper for Reader Focus Recovery State Machine
class ReaderFocusStateMachine {
  ReaderFocusStateMachine({
    required this.focusNode,
    this.bottomBarOffstage = true,
  });

  final FocusNode focusNode;
  bool bottomBarOffstage;
  bool selectionClearLocked = false;
  bool selectionClearPending = false;
  int focusRequestedCount = 0;

  void requestReaderFocus() {
    if (bottomBarOffstage && !focusNode.hasFocus) {
      focusNode.requestFocus();
      focusRequestedCount++;
    }
  }

  void restoreReaderFocus() {
    requestReaderFocus();
  }

  void setSelectionClearLocked(bool locked) {
    selectionClearLocked = locked;
    if (!locked && selectionClearPending) {
      selectionClearPending = false;
      restoreReaderFocus();
    }
  }

  void onSelectionCleared() {
    if (selectionClearLocked) {
      selectionClearPending = true;
      return;
    }
    restoreReaderFocus();
  }

  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;
    if (logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.pageDown ||
        logicalKey == LogicalKeyboardKey.space) {
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.pageUp) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reading Focus Recovery & Key Handling Contract Tests (#966)', () {
    late FocusNode readerFocusNode;
    late FocusNode otherFocusNode;
    late ReaderFocusStateMachine stateMachine;

    setUp(() {
      readerFocusNode = FocusNode(debugLabel: 'readerFocusNode');
      otherFocusNode = FocusNode(debugLabel: 'otherFocusNode');
      stateMachine = ReaderFocusStateMachine(focusNode: readerFocusNode);
    });

    tearDown(() {
      readerFocusNode.dispose();
      otherFocusNode.dispose();
    });

    testWidgets(
      'GIVEN reader is focused, WHEN arrow key is pressed, THEN event is handled',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Focus(
                focusNode: readerFocusNode,
                onKeyEvent: stateMachine.handleKeyEvent,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        );

        readerFocusNode.requestFocus();
        await tester.pump();
        expect(readerFocusNode.hasFocus, isTrue);

        const rightArrowEvent = KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowRight,
          logicalKey: LogicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        );
        final result = stateMachine.handleKeyEvent(readerFocusNode, rightArrowEvent);
        expect(result, equals(KeyEventResult.handled));
      },
    );

    testWidgets(
      'GIVEN reader lost focus to another node (e.g. text selection in WebView), WHEN arrow key is pressed, THEN event is ignored (reproducing #966 bug)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Focus(
                    focusNode: readerFocusNode,
                    onKeyEvent: stateMachine.handleKeyEvent,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                  Focus(
                    focusNode: otherFocusNode,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                ],
              ),
            ),
          ),
        );

        otherFocusNode.requestFocus();
        await tester.pump();
        expect(readerFocusNode.hasFocus, isFalse);

        const rightArrowEvent = KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowRight,
          logicalKey: LogicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        );
        final result = stateMachine.handleKeyEvent(readerFocusNode, rightArrowEvent);
        expect(result, equals(KeyEventResult.ignored));
      },
    );

    testWidgets(
      'GIVEN reader lost focus, WHEN onSelectionCleared is triggered, THEN restoreReaderFocus recovers focus to reader',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Focus(
                    focusNode: readerFocusNode,
                    onKeyEvent: stateMachine.handleKeyEvent,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                  Focus(
                    focusNode: otherFocusNode,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                ],
              ),
            ),
          ),
        );

        otherFocusNode.requestFocus();
        await tester.pump();
        expect(readerFocusNode.hasFocus, isFalse);

        // Selection is cleared
        stateMachine.onSelectionCleared();
        await tester.pump();

        expect(readerFocusNode.hasFocus, isTrue);
        expect(stateMachine.focusRequestedCount, equals(1));

        // Arrow key should now be handled again
        const leftArrowEvent = KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          logicalKey: LogicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        );
        final result = stateMachine.handleKeyEvent(readerFocusNode, leftArrowEvent);
        expect(result, equals(KeyEventResult.handled));
      },
    );

    testWidgets(
      'EDGE CASE 1: GIVEN bottomBarOffstage is false (menu visible), WHEN restoreReaderFocus is called, THEN does NOT steal focus',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Focus(
                    focusNode: readerFocusNode,
                    onKeyEvent: stateMachine.handleKeyEvent,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                  Focus(
                    focusNode: otherFocusNode,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                ],
              ),
            ),
          ),
        );

        otherFocusNode.requestFocus();
        stateMachine.bottomBarOffstage = false; // Menus are visible
        await tester.pump();

        stateMachine.restoreReaderFocus();
        await tester.pump();

        expect(readerFocusNode.hasFocus, isFalse);
        expect(stateMachine.focusRequestedCount, equals(0));
      },
    );

    testWidgets(
      'EDGE CASE 2: GIVEN selection is locked, WHEN cleared, THEN pending until unlocked, THEN restores focus',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Focus(
                    focusNode: readerFocusNode,
                    onKeyEvent: stateMachine.handleKeyEvent,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                  Focus(
                    focusNode: otherFocusNode,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                ],
              ),
            ),
          ),
        );

        otherFocusNode.requestFocus();
        await tester.pump();

        // Lock selection clear (e.g. context menu active)
        stateMachine.setSelectionClearLocked(true);
        stateMachine.onSelectionCleared();
        await tester.pump();

        // While locked, focus should not be restored yet
        expect(stateMachine.selectionClearPending, isTrue);
        expect(readerFocusNode.hasFocus, isFalse);

        // Unlock (e.g. context menu dismissed)
        stateMachine.setSelectionClearLocked(false);
        await tester.pump();

        expect(stateMachine.selectionClearPending, isFalse);
        expect(readerFocusNode.hasFocus, isTrue);
        expect(stateMachine.focusRequestedCount, equals(1));
      },
    );
  });
}
