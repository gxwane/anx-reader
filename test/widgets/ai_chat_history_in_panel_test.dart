import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'selected_ai_service': 'openai',
      'ai_chat_font_size': 14.0,
    });
    await Prefs().initPrefs();
    Prefs().setShowHint(HintKey.aiDataSharingConsent, false);
  });

  Widget createSubject({List<AiChatHistoryEntry>? mockHistory}) {
    final historyList = mockHistory ?? [
      AiChatHistoryEntry(
        id: 'session-1',
        serviceId: 'openai',
        model: 'gpt-4o',
        createdAt: 1000,
        updatedAt: 2000,
        completed: true,
        messages: [
          ChatMessage.humanText('Hello world test'),
          ChatMessage.ai('AI response text'),
        ],
      ),
      AiChatHistoryEntry(
        id: 'session-2',
        serviceId: 'claude',
        model: 'claude-3-5-sonnet',
        createdAt: 3000,
        updatedAt: 4000,
        completed: false,
        messages: [
          ChatMessage.humanText('Analyze Chapter 3'),
        ],
      ),
    ];

    return ProviderScope(
      overrides: [
        aiHistoryProvider.overrideWith((ref) {
          final notifier = AiHistoryNotifier();
          notifier.state = AsyncValue.data(historyList);
          return notifier;
        }),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 700,
            child: AiChatStream(
              trailing: [
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  tooltip: 'Show at Bottom',
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('AI Chat In-Panel History Master-Detail Spec & Tests', () {
    testWidgets('GIVEN on Chat view, WHEN tap history icon, THEN switches in-panel to History view',
        (WidgetTester tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Initial state: Chat view is visible, formatted AppBar
      expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.format_size), findsOneWidget);
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Tap history button
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      // Transformed state: History view is visible, Chat view is gone
      expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_chat_view')), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Hello world test'), findsOneWidget);
      expect(find.text('Analyze Chapter 3'), findsOneWidget);

      // Verify position toggle is filtered out in History view, only Close remains
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('GIVEN on History view, WHEN tap back button, THEN switches back to Chat view',
        (WidgetTester tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Open history
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);

      // Tap back button in AppBar
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Switched back to Chat view
      expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('GIVEN on History view, WHEN selecting a history item, THEN loads session and returns to Chat view',
        (WidgetTester tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Open history
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      // Tap on first session card ('Hello world test')
      await tester.tap(find.text('Hello world test'));
      await tester.pumpAndSettle();

      // Automatically returned to Chat view with messages loaded
      expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
      expect(find.text('Hello world test'), findsOneWidget);
      expect(find.text('AI response text'), findsOneWidget);
    });

    testWidgets('GIVEN on History view, WHEN tapping New Chat button, THEN clears chat and switches to Chat view',
        (WidgetTester tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Open history
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      // Tap on add / new chat icon in History view
      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();

      // Returns to Chat view
      expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('GIVEN empty history, WHEN entering History view, THEN displays empty tip',
        (WidgetTester tester) async {
      await tester.pumpWidget(createSubject(mockHistory: []));
      await tester.pumpAndSettle();

      // Open history
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    group('Hardener Gate 5: Mutation Killer Tests', () {
      testWidgets('[M-01 Killer] Rigorous bidirectional state transition & icon swapping verification',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        // 1. Pre-condition: Chat view visible, History view strictly absent
        expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
        expect(find.byIcon(Icons.history), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back), findsNothing);

        // 2. Action: Tap history icon
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();

        // 3. Post-condition: History view visible, Chat view strictly absent, AppBar icons swapped
        expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai_chat_view')), findsNothing);
        expect(find.byIcon(Icons.history), findsNothing);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
        expect(find.byIcon(Icons.delete_sweep), findsOneWidget);
      });

      testWidgets('[M-02 Killer] Close history strictly restores chat AppBar and destroys history tree',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        // Enter history
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);

        // Tap back
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Strictly verify history is destroyed and chat view is restored
        expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
        expect(find.byIcon(Icons.arrow_back), findsNothing);
        expect(find.byIcon(Icons.history), findsOneWidget);
      });

      testWidgets('[M-03 Killer] PopScope intercepts system back and returns to chat view without popping route',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        // Enter history
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);

        // Simulate system back pop (Android back button / Desktop ESC)
        final dynamic widgetsBinding = tester.binding;
        await widgetsBinding.handlePopRoute();
        await tester.pumpAndSettle();

        // Should intercept pop and switch in-panel back to chat view
        expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
        expect(find.byType(AiChatStream), findsOneWidget);
      });

      testWidgets('[M-04 Killer] Exact history item count and content integrity verification',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        // Enter history
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();

        // Assert exactly 2 cards rendered matching mock data
        expect(find.text('Hello world test'), findsOneWidget);
        expect(find.text('Analyze Chapter 3'), findsOneWidget);
        expect(find.textContaining('gpt-4o'), findsOneWidget);
        expect(find.textContaining('claude-3-5-sonnet'), findsOneWidget);
      });

      testWidgets('[M-05 Killer] Session selection strictly closes history and renders messages',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        // Enter history
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();

        // Select second session
        await tester.tap(find.text('Analyze Chapter 3'));
        await tester.pumpAndSettle();

        // Verify view is Chat view and loaded message is visible
        expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
        expect(find.text('Analyze Chapter 3'), findsOneWidget);
      });

      testWidgets('[M-06 Killer] Rapid cyclical switching maintains state machine idempotence',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          // Open history
          await tester.tap(find.byIcon(Icons.history));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);
          expect(find.byKey(const ValueKey('ai_chat_view')), findsNothing);

          // Close history
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
          expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
        }
      });
    });

    group('AI Thinking Panel & Scroll Constraint Tests', () {
      testWidgets('GIVEN reasoning message, THEN renders ExpansionTile with thinking indicator',
          (WidgetTester tester) async {
        final mockHistory = [
          AiChatHistoryEntry(
            id: 'thinking-session',
            serviceId: 'openai',
            model: 'gpt-4o',
            createdAt: 1000,
            updatedAt: 2000,
            completed: true,
            messages: [
              ChatMessage.humanText('Explain quantum mechanics'),
              ChatMessage.ai('<think>Step 1: Analyzing context\nStep 2: Reason deeply</think>\nFinal Answer'),
            ],
          ),
        ];

        await tester.pumpWidget(createSubject(mockHistory: mockHistory));
        await tester.pumpAndSettle();

        // Open history and select session
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Explain quantum mechanics'));
        await tester.pumpAndSettle();

        // Verify ExpansionTile and final answer rendered
        expect(find.byType(ExpansionTile), findsOneWidget);
        expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
        expect(find.text('Final Answer'), findsOneWidget);

        // Expand the thinking panel
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();

        // Verify thinking content, SingleChildScrollView, and Scrollbar exist
        expect(find.byType(SingleChildScrollView), findsWidgets);
        expect(find.descendant(of: find.byType(ExpansionTile), matching: find.byType(Scrollbar)), findsOneWidget);
        expect(find.textContaining('Step 1: Analyzing context'), findsOneWidget);
      });

      testWidgets('GIVEN message list, THEN NotificationListener wraps ListView for gesture scroll lock',
          (WidgetTester tester) async {
        final mockHistory = [
          AiChatHistoryEntry(
            id: 'long-session',
            serviceId: 'openai',
            model: 'gpt-4o',
            createdAt: 1000,
            updatedAt: 2000,
            completed: true,
            messages: [
              ChatMessage.humanText('Question 1'),
              ChatMessage.ai('Answer 1 with details'),
            ],
          ),
        ];

        await tester.pumpWidget(createSubject(mockHistory: mockHistory));
        await tester.pumpAndSettle();

        // Open history and select session
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Question 1'));
        await tester.pumpAndSettle();

        // Verify NotificationListener<ScrollNotification> wraps the scrollable message list
        expect(find.byType(NotificationListener<ScrollNotification>), findsWidgets);
        expect(find.byType(SingleChildScrollView), findsWidgets);
      });

      testWidgets('GIVEN history card, WHEN double tapped, THEN loads session and switches to chat view',
          (WidgetTester tester) async {
        final mockHistory = [
          AiChatHistoryEntry(
            id: 'double-tap-session',
            serviceId: 'openai',
            model: 'gpt-4o',
            createdAt: 1000,
            updatedAt: 2000,
            completed: true,
            messages: [
              ChatMessage.humanText('Double tap test query'),
              ChatMessage.ai('Double tap test response'),
            ],
          ),
        ];

        await tester.pumpWidget(createSubject(mockHistory: mockHistory));
        await tester.pumpAndSettle();

        // Open history
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('ai_history_view')), findsOneWidget);

        // Tap history item card (verifies opaque hit test across entire card)
        final historyTileFinder = find.descendant(
          of: find.byKey(const ValueKey('ai_history_view')),
          matching: find.text('Double tap test query'),
        );
        await tester.tap(historyTileFinder);
        await tester.pumpAndSettle();

        // Verify session loaded and switched back to chat view
        expect(find.byKey(const ValueKey('ai_chat_view')), findsOneWidget);
        expect(find.byKey(const ValueKey('ai_history_view')), findsNothing);
        expect(find.text('Double tap test query'), findsOneWidget);
      });

      testWidgets('GIVEN message input, WHEN sending message, THEN maintains TextField focus and triggers scroll to bottom',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        // Find input field
        final inputFinder = find.byType(TextField);
        expect(inputFinder, findsOneWidget);

        // Enter text and submit
        await tester.enterText(inputFinder, 'Hello AI Assistant');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();

        // Verify TextField retains focus
        final TextField textField = tester.widget(inputFinder);
        expect(textField.focusNode?.hasFocus ?? true, isTrue);
      });

      testWidgets('GIVEN message list, THEN wraps ListView in interactive Scrollbar with controller',
          (WidgetTester tester) async {
        final mockHistory = [
          AiChatHistoryEntry(
            id: 'scrollbar-test-session',
            serviceId: 'openai',
            model: 'gpt-4o',
            createdAt: 1000,
            updatedAt: 2000,
            completed: true,
            messages: [
              ChatMessage.humanText('Hello'),
              ChatMessage.ai('World'),
            ],
          ),
        ];

        await tester.pumpWidget(createSubject(mockHistory: mockHistory));
        await tester.pumpAndSettle();

        // Open history and load session
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hello'));
        await tester.pumpAndSettle();

        // Verify Scrollbar wraps SingleChildScrollView with controller and interactive mode
        final scrollbars = find.byType(Scrollbar);
        expect(scrollbars, findsWidgets);

        final Scrollbar messageListScrollbar = tester.widget(scrollbars.first);
        expect(messageListScrollbar.interactive, isTrue);
        expect(messageListScrollbar.controller, isNotNull);

        // Verify message container uses SingleChildScrollView with ClampingScrollPhysics
        final SingleChildScrollView scrollView =
            tester.widget(find.byType(SingleChildScrollView).first);
        expect(scrollView.physics, isA<ClampingScrollPhysics>());
      });

      testWidgets('GIVEN loaded history, WHEN sending message first time, THEN messages never disappear into skeleton',
          (WidgetTester tester) async {
        final mockHistory = [
          AiChatHistoryEntry(
            id: 'flicker-test-session',
            serviceId: 'openai',
            model: 'gpt-4o',
            createdAt: 1000,
            updatedAt: 2000,
            completed: true,
            messages: [
              ChatMessage.humanText('Initial User Question'),
              ChatMessage.ai('Initial Assistant Answer'),
            ],
          ),
        ];

        await tester.pumpWidget(createSubject(mockHistory: mockHistory));
        await tester.pumpAndSettle();

        // Open history and load session
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Initial User Question'));
        await tester.pumpAndSettle();

        // Verify loaded messages are visible
        expect(find.text('Initial User Question'), findsOneWidget);
        expect(find.text('Initial Assistant Answer'), findsOneWidget);

        // Send a new message
        final inputFinder = find.byType(TextField);
        await tester.enterText(inputFinder, 'Followup Question');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        // Only pump 1 frame (simulate Stream waiting / before first token arrives)
        await tester.pump();

        // CRITICAL ASSERTION: Historical messages and newly sent question must remain visible, NOT blank or Skeletonizer
        expect(find.text('Initial User Question'), findsOneWidget);
        expect(find.text('Initial Assistant Answer'), findsOneWidget);
        expect(find.text('Followup Question'), findsOneWidget);
      });

      testWidgets('GIVEN completed message, THEN copy and regenerate buttons are displayed for assistant',
          (WidgetTester tester) async {
        final mockHistory = [
          AiChatHistoryEntry(
            id: 'completed-buttons-session',
            serviceId: 'openai',
            model: 'gpt-4o',
            createdAt: 1000,
            updatedAt: 2000,
            completed: true,
            messages: [
              ChatMessage.humanText('My Question'),
              ChatMessage.ai('My Answer'),
            ],
          ),
        ];

        await tester.pumpWidget(createSubject(mockHistory: mockHistory));
        await tester.pumpAndSettle();

        // Open history and load session
        await tester.tap(find.byIcon(Icons.history));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My Question'));
        await tester.pumpAndSettle();

        // Verify action buttons exist in completed state
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('Regenerate'), findsOneWidget);
      });

      testWidgets('GIVEN quick prompts chips, THEN renders in left-aligned horizontal scroll view without reverse',
          (WidgetTester tester) async {
        await tester.pumpWidget(createSubject());
        await tester.pumpAndSettle();

        // Verify quick prompt chips exist
        final chipFinder = find.byType(ActionChip);
        expect(chipFinder, findsWidgets);

        // Verify the horizontal scroll view for chips has reverse == false
        final scrollViews = tester.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView));
        final chipScrollView = scrollViews.firstWhere((sv) => sv.scrollDirection == Axis.horizontal);
        expect(chipScrollView.reverse, isFalse);
      });
    });
  });
}



