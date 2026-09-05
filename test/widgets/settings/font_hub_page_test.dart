import 'dart:ui';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/providers/fonts.dart';
import 'package:anx_reader/service/font/system_font_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFonts extends Fonts {
  final List<RemoteFontModel> data;
  FakeFonts([this.data = const []]);

  @override
  Future<List<RemoteFontModel>> build() async {
    return data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FontsSettingPage (Font Hub) UI & Tabs', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      SystemFontService.instance.setMockSystemFonts(['Microsoft YaHei', 'Arial', 'SimSun']);
    });

    tearDown(() {
      SystemFontService.instance.setMockSystemFonts(null);
    });

    testWidgets('renders all 3 tabs and shows active font in My Fonts', (tester) async {
      final container = ProviderContainer(
        overrides: [
          fontsProvider.overrideWith(() => FakeFonts()),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('en'),
              home: FontsSettingPage(initialTabIndex: 0),
            ),
          ),
        );

        await container.read(fontListProvider.future);
      });

      await tester.pump();

      // Verify 3 tabs present
      expect(find.byType(Tab), findsNWidgets(3));

      // Verify active font badge "In Use" is visible
      expect(find.text('In Use'), findsOneWidget);
    });

    testWidgets('renders System Fonts tab search input', (tester) async {
      final container = ProviderContainer(
        overrides: [
          fontsProvider.overrideWith(() => FakeFonts()),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('en'),
              home: FontsSettingPage(initialTabIndex: 1),
            ),
          ),
        );

        await container.read(fontListProvider.future);
      });

      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('tapping font tile updates Prefs().font', (tester) async {
      final container = ProviderContainer(
        overrides: [
          fontsProvider.overrideWith(() => FakeFonts()),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('en'),
              home: Scaffold(
                body: FontsSettingPage(initialTabIndex: 0),
              ),
            ),
          ),
        );

        await container.read(fontListProvider.future);
      });

      await tester.pump();

      final systemFontTile = find.widgetWithText(ListTile, 'System Font');
      expect(systemFontTile, findsOneWidget);
      await tester.tap(systemFontTile);
      await tester.pump();
      expect(Prefs().font.id, equals('preset:system'));
    });

    testWidgets('Tab 3 renders search bar, file size, and filters online fonts', (tester) async {
      final fakeData = [
        const RemoteFontModel(
          id: 'test_font_1',
          name: 'Alpha Font',
          files: ['alpha/Alpha-Regular.ttf'],
          size: 1572864, // 1.5 MB
          preview: '',
          desc: 'A beautiful alpha serif font',
          official: 'https://example.com/alpha',
          license: LicenseModel(name: 'OFL', url: 'https://example.com/license'),
        ),
        const RemoteFontModel(
          id: 'test_font_2',
          name: 'Beta Sans',
          files: ['beta/Beta-Regular.ttf'],
          size: 65536, // 64 KB
          preview: '',
          desc: 'A smooth sans-serif font',
          official: 'https://example.com/beta',
          license: LicenseModel(name: 'MIT', url: 'https://example.com/license'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          fontsProvider.overrideWith(() => FakeFonts(fakeData)),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('en'),
              home: Scaffold(
                body: FontsSettingPage(initialTabIndex: 2),
              ),
            ),
          ),
        );

        await container.read(fontListProvider.future);
      });

      await tester.pumpAndSettle();

      // Verify search bar with online search hint
      expect(find.text('Search online fonts...'), findsOneWidget);

      // Verify fonts and size labels rendered
      expect(find.text('Alpha Font'), findsOneWidget);
      expect(find.text('Beta Sans'), findsOneWidget);
      expect(find.text('1.5 MB'), findsOneWidget);
      expect(find.text('64 KB'), findsOneWidget);

      // Filter by "Beta"
      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();

      expect(find.text('Beta Sans'), findsOneWidget);
      expect(find.text('Alpha Font'), findsNothing);

      // Filter by non-existent font
      await tester.enterText(find.byType(TextField), 'NonExistent');
      await tester.pumpAndSettle();

      expect(find.text('No matching fonts found'), findsOneWidget);
    });

    testWidgets('Tab 3 renders font source switcher button and opens dialog', (tester) async {
      final fakeData = [
        const RemoteFontModel(
          id: 'test_font_1',
          name: 'Alpha Font',
          files: ['alpha/Alpha-Regular.ttf'],
          size: 1024,
          preview: '',
          desc: 'Test font',
          official: 'https://example.com',
          license: LicenseModel(name: 'OFL', url: 'https://example.com'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          fontsProvider.overrideWith(() => FakeFonts(fakeData)),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('en'),
              home: Scaffold(
                body: FontsSettingPage(initialTabIndex: 2),
              ),
            ),
          ),
        );

        await container.read(fontListProvider.future);
      });

      await tester.pumpAndSettle();

      // Verify font source switcher button is visible
      expect(find.text('Official Store'), findsOneWidget);

      // Tap font source switcher button
      await tester.tap(find.text('Official Store'));
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Font Sources'), findsOneWidget);
      expect(find.text('Add Font Source'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Official'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Tab 3 shows offline notice when manifest is cached', (tester) async {
      final fakeData = [
        const RemoteFontModel(
          id: 'test_font_1',
          name: 'Alpha Font',
          files: ['alpha/Alpha-Regular.ttf'],
          size: 1024,
          preview: '',
          desc: 'Test font',
          official: 'https://example.com',
          license: LicenseModel(name: 'OFL', url: 'https://example.com'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          fontsProvider.overrideWith(() => FakeFonts(fakeData)),
          onlineFontsIsCacheProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: Locale('en'),
              home: Scaffold(
                body: FontsSettingPage(initialTabIndex: 2),
              ),
            ),
          ),
        );

        await container.read(fontListProvider.future);
      });

      await tester.pumpAndSettle();

      // Verify offline banner text is visible
      expect(find.text('Showing offline cached fonts'), findsOneWidget);
    });

    testWidgets('on Windows desktop: Font Hub tabs handle mouse hover and scrollbar drag without error', (tester) async {
      final container = ProviderContainer(
        overrides: [
          fontsProvider.overrideWith(() => FakeFonts()),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.windows),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: const Locale('en'),
              home: const Scaffold(
                body: FontsSettingPage(initialTabIndex: 0),
              ),
            ),
          ),
        );

        await container.read(fontListProvider.future);
      });

      await tester.pumpAndSettle();
      expect(find.byType(FontsSettingPage), findsOneWidget);

      // Verify mouse hover over scrollbar area triggers no "no ScrollPosition attached" crash
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(790, 100));
      await tester.pumpAndSettle();
      await gesture.down(const Offset(790, 100));
      await gesture.moveTo(const Offset(790, 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(FontsSettingPage), findsOneWidget);
    });
  });
}

