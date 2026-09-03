import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/service/font/system_font_service.dart';
import 'package:anx_reader/widgets/reading_page/font_manager_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FontManagerModal & System Font Pinning', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      SystemFontService.instance.setMockSystemFonts(['Microsoft YaHei', 'Arial', 'SimSun']);
    });

    tearDown(() {
      SystemFontService.instance.setMockSystemFonts(null);
    });

    test('togglePinSystemFont updates Prefs and fontListProvider state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Verify initially unpinned
      expect(Prefs().pinnedSystemFonts, isEmpty);

      // Pin a test system font
      await container.read(fontListProvider.notifier).togglePinSystemFont('Microsoft YaHei');
      expect(Prefs().pinnedSystemFonts, contains('Microsoft YaHei'));

      // Check font list provider includes it
      final fonts = await container.read(fontListProvider.future);
      expect(fonts.any((f) => f.id == 'system:Microsoft YaHei' && f.source == FontSource.systemFont), isTrue);

      // Toggle again to unpin
      await container.read(fontListProvider.notifier).togglePinSystemFont('Microsoft YaHei');
      expect(Prefs().pinnedSystemFonts, isNot(contains('Microsoft YaHei')));

      final fontsAfterUnpin = await container.read(fontListProvider.future);
      expect(fontsAfterUnpin.any((f) => f.id == 'system:Microsoft YaHei'), isFalse);
    });

    test('unpinning active font resets Prefs().font to book preset', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(fontListProvider.notifier).togglePinSystemFont('Microsoft YaHei');
      Prefs().font = FontModel.systemFont(familyName: 'Microsoft YaHei');
      expect(Prefs().font.id, equals('system:Microsoft YaHei'));

      // Unpin
      await container.read(fontListProvider.notifier).togglePinSystemFont('Microsoft YaHei');
      expect(Prefs().font.id, equals('preset:book'));
    });

    testWidgets('FontManagerModal builds cleanly and displays search input', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const Scaffold(
              body: FontManagerModal(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.font_download_outlined), findsOneWidget);
    });
  });
}
