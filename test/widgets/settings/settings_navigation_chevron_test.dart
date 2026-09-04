import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/advanced.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  group('SettingsTile Navigation vs Action Tile UX Alignment Tests', () {
    testWidgets('AppearanceSetting: only Font Hub has navigation tile, theme & language are simple tiles', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: AppearanceSetting(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<SettingsTile>(find.byType(SettingsTile)).toList();

      // Find font management tile (navigates to subpage FontsSettingPage)
      final fontTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Font Management',
      );
      expect(fontTile.tileType, equals(SettingsTileType.navigationTile));

      // Find theme color tile (dialog picker, not a subpage)
      final themeTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Theme Color',
      );
      expect(themeTile.tileType, equals(SettingsTileType.simpleTile));

      // Find language tile (dialog picker, not a subpage)
      final langTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Language',
      );
      expect(langTile.tileType, equals(SettingsTileType.simpleTile));
    });

    testWidgets('SyncSetting: WebDAV settings has navigation tile, actions are simple tiles', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: Locale('en'),
            home: Scaffold(
              body: SyncSetting(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<SettingsTile>(find.byType(SettingsTile)).toList();

      // WebDAV configuration entry
      final webdavTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'WebDAV',
      );
      expect(webdavTile.tileType, equals(SettingsTileType.navigationTile));

      // Export data is an immediate action / picker
      final exportTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Export',
      );
      expect(exportTile.tileType, equals(SettingsTileType.simpleTile));

      // Import data is an immediate action / picker
      final importTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Import',
      );
      expect(importTile.tileType, equals(SettingsTileType.simpleTile));

      // Restore backup is a modal dialog
      final restoreTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Restore Backup',
      );
      expect(restoreTile.tileType, equals(SettingsTileType.simpleTile));

      // Sync now is an immediate background action
      final syncNowTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Sync Now',
      );
      expect(syncNowTile.tileType, equals(SettingsTileType.simpleTile));

      // Export markdown is an immediate background action
      final exportMdTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Mirror All Notes to WebDAV Now',
      );
      expect(exportMdTile.tileType, equals(SettingsTileType.simpleTile));
    });

    testWidgets('AdvancedSetting: ChapterSplit, Log, Changelog, and Onboarding have navigation tiles, MD5 and hints are simple tiles', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: AdvancedSetting(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<SettingsTile>(find.byType(SettingsTile)).toList();

      // Chapter split rules has a subpage
      final chapterTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Chapter splitting',
      );
      expect(chapterTile.tileType, equals(SettingsTileType.navigationTile));

      // Log page has a subpage
      final logTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Log',
      );
      expect(logTile.tileType, equals(SettingsTileType.navigationTile));

      // Changelog sheet is a navigation tile
      final changelogTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'View changelog',
      );
      expect(changelogTile.tileType, equals(SettingsTileType.navigationTile));

      // Onboarding sheet is a navigation tile
      final onboardingTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'View onboarding',
      );
      expect(onboardingTile.tileType, equals(SettingsTileType.navigationTile));

      // Recalculate MD5 is an in-place action
      final md5Tile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Calculate Missing MD5',
      );
      expect(md5Tile.tileType, equals(SettingsTileType.simpleTile));

      // Show hints again is an immediate action
      final hintsTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Show all hints again',
      );
      expect(hintsTile.tileType, equals(SettingsTileType.simpleTile));
    });

    testWidgets('AISettings: providers tile is navigation, prompts and clear cache are simple tiles', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: Locale('en'),
            home: Scaffold(
              body: AISettings(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<SettingsTile>(find.byType(SettingsTile)).toList();

      // AI providers navigates to subpage AiProviderListPage
      final providerTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Provider Center',
      );
      expect(providerTile.tileType, equals(SettingsTileType.navigationTile));

      // AI prompt items open edit modal dialogs
      final promptTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Test AI config',
      );
      expect(promptTile.tileType, equals(SettingsTileType.simpleTile));

      // Clear cache is an in-place action with confirmation dialog
      final clearCacheTile = tiles.firstWhere(
        (tile) => tile.title is Text && (tile.title as Text).data == 'Clear cache',
      );
      expect(clearCacheTile.tileType, equals(SettingsTileType.simpleTile));
    });
  });
}
