import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'selected_ai_service': 'openai',
      'ai_chat_font_size': 14.0,
      'aiPromptSendImmediately': false,
    });
    await Prefs().initPrefs();
    Prefs().setShowHint(HintKey.aiDataSharingConsent, false);
    Prefs().aiPromptSendImmediately = false;
  });

  Widget createSubject({
    List<AiQuickPromptChip>? quickPromptChips,
    GlobalKey<AiChatStreamState>? streamKey,
  }) {
    return ProviderScope(
      overrides: [
        aiHistoryProvider.overrideWith((ref) {
          final notifier = AiHistoryNotifier();
          notifier.state = const AsyncValue.data([]);
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
            width: 700,
            height: 700,
            child: AiChatStream(
              key: streamKey,
              quickPromptChips: quickPromptChips ?? const [],
            ),
          ),
        ),
      ),
    );
  }

  group('AI Prompt Template Fill & Fine-Tuning Specification (TDD #969)', () {
    testWidgets('GIVEN default settings, WHEN tapping contextual prompt chip, THEN fills text without sending',
        (WidgetTester tester) async {
      final streamKey = GlobalKey<AiChatStreamState>();
      await tester.pumpWidget(createSubject(streamKey: streamKey));
      await tester.pumpAndSettle();

      final state = streamKey.currentState!;
      expect(state.inputController.text, isEmpty);

      // Find "Explain" chip in input box
      final explainChip = find.widgetWithText(ActionChip, 'Explain');
      expect(explainChip, findsOneWidget);

      // Tap Explain chip
      await tester.tap(explainChip);
      await tester.pumpAndSettle();

      // Verified: Text is filled with trailing space for editing and not cleared by sending
      expect(state.inputController.text, 'Please explain ');
      expect(state.inputController.selection.baseOffset, state.inputController.text.length);
      expect(find.byIcon(Icons.stop), findsNothing);
    });

    testWidgets('GIVEN existing excerpt text, WHEN switching prefix prompt chips, THEN replaces prefix cleanly without duplication',
        (WidgetTester tester) async {
      final streamKey = GlobalKey<AiChatStreamState>();
      await tester.pumpWidget(createSubject(streamKey: streamKey));
      await tester.pumpAndSettle();

      final state = streamKey.currentState!;
      state.inputController.text = 'Quantum entanglement';

      // Tap Explain chip
      await tester.tap(find.widgetWithText(ActionChip, 'Explain'));
      await tester.pumpAndSettle();
      expect(state.inputController.text, 'Please explain Quantum entanglement');

      // Now switch to Analyze chip
      await tester.tap(find.widgetWithText(ActionChip, 'Analyze'));
      await tester.pumpAndSettle();

      // Verified: Replaced "Please explain" with "Please analyze" without stacking
      expect(state.inputController.text, 'Please analyze Quantum entanglement');
      expect(state.inputController.selection.baseOffset, state.inputController.text.length);
    });

    testWidgets('GIVEN quickPromptChips in empty state, WHEN tapped, THEN fills into input box',
        (WidgetTester tester) async {
      final streamKey = GlobalKey<AiChatStreamState>();
      final customChips = [
        const AiQuickPromptChip(
          icon: Icons.book,
          label: 'Chapter Summary',
          prompt: 'Summarize this chapter thoroughly.',
        ),
      ];

      await tester.pumpWidget(createSubject(
        streamKey: streamKey,
        quickPromptChips: customChips,
      ));
      await tester.pumpAndSettle();

      final state = streamKey.currentState!;
      expect(state.inputController.text, isEmpty);

      // Tap "Chapter Summary" chip in empty state
      await tester.tap(find.widgetWithText(ActionChip, 'Chapter Summary'));
      await tester.pumpAndSettle();

      expect(state.inputController.text, 'Summarize this chapter thoroughly.');
      expect(state.inputController.selection.baseOffset, state.inputController.text.length);
      expect(find.byIcon(Icons.stop), findsNothing);
    });

    testWidgets('GIVEN default settings, WHEN long-pressing prompt chip, THEN sends message directly (fast-track)',
        (WidgetTester tester) async {
      final streamKey = GlobalKey<AiChatStreamState>();
      await tester.pumpWidget(createSubject(streamKey: streamKey));
      await tester.pumpAndSettle();

      final state = streamKey.currentState!;
      state.inputController.text = 'Important passage';

      // Long-press Explain chip
      await tester.longPress(find.widgetWithText(ActionChip, 'Explain'));
      await tester.pump();

      // Verified: Input was submitted/cleared and stream started
      expect(state.inputController.text, isEmpty);
    });

    testWidgets('GIVEN aiPromptSendImmediately is true, WHEN tapping prompt chip, THEN sends immediately',
        (WidgetTester tester) async {
      Prefs().aiPromptSendImmediately = true;

      final streamKey = GlobalKey<AiChatStreamState>();
      await tester.pumpWidget(createSubject(streamKey: streamKey));
      await tester.pumpAndSettle();

      final state = streamKey.currentState!;
      state.inputController.text = 'Immediate test';

      // Tap Explain chip
      await tester.tap(find.widgetWithText(ActionChip, 'Explain'));
      await tester.pump();

      // Verified: Message submitted immediately
      expect(state.inputController.text, isEmpty);
    });
  });
}
