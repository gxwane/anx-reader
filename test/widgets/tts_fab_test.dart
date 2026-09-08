import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/widgets/reading_page/tts_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final epubPlayerKey = GlobalKey<EpubPlayerState>();
  late ValueNotifier<bool> decoupledNotifier;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  setUp(() {
    decoupledNotifier = ValueNotifier<bool>(false);
    TtsHandler().ttsStateNotifier.value = TtsStateEnum.stopped;
  });

  tearDown(() {
    decoupledNotifier.dispose();
  });

  Widget buildTestWidget({
    Future<void> Function()? onReturnToVoice,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            TtsFab(
              epubPlayerKey: epubPlayerKey,
              decoupledNotifierForTest: decoupledNotifier,
              onReturnToVoiceForTest: onReturnToVoice,
            ),
          ],
        ),
      ),
    );
  }

  group('TtsFab Widget Morphing & Decoupled Tests', () {
    testWidgets('Hidden when TTS is stopped even if decoupled is true',
        (tester) async {
      decoupledNotifier.value = true;
      TtsHandler().ttsStateNotifier.value = TtsStateEnum.stopped;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final animatedOpacityFinder = find.byWidgetPredicate(
        (widget) => widget is AnimatedOpacity && widget.opacity == 0.0,
      );
      expect(animatedOpacityFinder, findsOneWidget);
    });

    testWidgets('Renders circular main FAB when TTS is playing and not decoupled',
        (tester) async {
      decoupledNotifier.value = false;
      TtsHandler().ttsStateNotifier.value = TtsStateEnum.playing;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tts-fab-main')), findsOneWidget);
      expect(find.byKey(const ValueKey('tts-fab-decoupled-pill')), findsNothing);
    });

    testWidgets('Morphs into Return to Voice Pill when playing and decoupled',
        (tester) async {
      decoupledNotifier.value = true;
      TtsHandler().ttsStateNotifier.value = TtsStateEnum.playing;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tts-fab-decoupled-pill')), findsOneWidget);
      expect(find.text('Return to Voice'), findsOneWidget);
      expect(find.byKey(const ValueKey('tts-fab-main')), findsNothing);
    });

    testWidgets('Tapping Return to Voice Pill triggers callback',
        (tester) async {
      bool returnTriggered = false;
      decoupledNotifier.value = true;
      TtsHandler().ttsStateNotifier.value = TtsStateEnum.playing;

      await tester.pumpWidget(buildTestWidget(
        onReturnToVoice: () async {
          returnTriggered = true;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tts-fab-decoupled-pill')));
      await tester.pumpAndSettle();

      expect(returnTriggered, isTrue);
    });
  });
}

