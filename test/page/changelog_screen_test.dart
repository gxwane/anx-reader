import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/changelog_screen.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestChangelogAssetBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'assets/CHANGELOG.md') {
      return '''
# Changelog

## [0.1.0-preview.5] - 2026-09-02
- Feat: Widget test new feature

- Feat: 单元测试新特性
''';
    }
    return '';
  }

  @override
  Future<ByteData> load(String key) async {
    return ByteData(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChangelogScreen pure functions (extractVersionChangelog & processChangelogContent)', () {
    const sampleChangelog = '''
# Changelog

## [0.1.0-preview.5] - 2026-09-02
- Feat(font): Online Font Store resilience
- Fix(settings): Standardize Settings navigation chevrons

- Feat(font): 在线字体库容灾韧性
- Fix(settings): 规范清理设置界面中的导航箭头

## [0.1.0] - 2026-08-30
- Feat: Base version release notes
- Fix: Base version fixes

- Feat: 基础版本功能
- Fix: 基础版本修复

## 1.12.0
- Feat: Legacy 1.12.0 English

- Feat: 历史 1.12.0 中文
''';

    test('extractVersionChangelog matches exact pre-release version', () {
      final result = extractVersionChangelog(sampleChangelog, '0.1.0-preview.5+5');
      expect(result, contains('Feat(font): Online Font Store resilience'));
      expect(result, contains('Fix(settings): 规范清理设置界面中的导航箭头'));
      expect(result, isNot(contains('Base version release notes')));
      expect(result, isNot(contains('Legacy 1.12.0')));
    });

    test('extractVersionChangelog matches base semver with bracketed and dated header', () {
      final result = extractVersionChangelog(sampleChangelog, '0.1.0');
      expect(result, contains('Base version release notes'));
      expect(result, contains('基础版本功能'));
      expect(result, isNot(contains('Online Font Store resilience')));
      expect(result, isNot(contains('Legacy 1.12.0')));
    });

    test('extractVersionChangelog boundary safety: base 0.1.0 does not false-match 0.1.0-preview.5', () {
      const changelogWithBoth = '''
## [0.1.0-preview.5]
- Pre-release note

## [0.1.0]
- Official base note
''';
      final baseResult = extractVersionChangelog(changelogWithBoth, '0.1.0');
      expect(baseResult, contains('Official base note'));
      expect(baseResult, isNot(contains('Pre-release note')));
    });

    test('extractVersionChangelog falls back to first section if version not found', () {
      final result = extractVersionChangelog(sampleChangelog, '9.9.9-dev+99');
      // Should gracefully fall back to latest top section
      expect(result, contains('Feat(font): Online Font Store resilience'));
      expect(result, isNot(contains('Legacy 1.12.0')));
    });

    test('extractVersionChangelog returns default content if changelog has no version headers', () {
      const emptyChangelog = '# Changelog\nSome plain text without headers';
      final result = extractVersionChangelog(emptyChangelog, '0.1.0');
      expect(result, equals(defaultChangelogContent));
    });

    test('processChangelogContent extracts only Chinese entries for Chinese locale', () {
      final extracted = extractVersionChangelog(sampleChangelog, '0.1.0-preview.5');
      final zhContent = processChangelogContent(extracted, isChinese: true);

      expect(zhContent, contains('Feat(font): 在线字体库容灾韧性'));
      expect(zhContent, contains('Fix(settings): 规范清理设置界面中的导航箭头'));
      expect(zhContent, isNot(contains('Online Font Store resilience')));
      expect(zhContent, isNot(contains('Standardize Settings navigation chevrons')));
    });

    test('processChangelogContent extracts only English entries for non-Chinese locale', () {
      final extracted = extractVersionChangelog(sampleChangelog, '0.1.0-preview.5');
      final enContent = processChangelogContent(extracted, isChinese: false);

      expect(enContent, contains('Feat(font): Online Font Store resilience'));
      expect(enContent, contains('Fix(settings): Standardize Settings navigation chevrons'));
      expect(enContent, isNot(contains('在线字体库容灾韧性')));
      expect(enContent, isNot(contains('规范清理设置界面中的导航箭头')));
    });

    test('processChangelogContent handles unbalanced line counts without cross-contamination', () {
      const unbalancedContent = '''
- English line 1
- English line 2
- English line 3
- English line 4

- 中文行 1
''';
      final zhResult = processChangelogContent(unbalancedContent, isChinese: true);
      expect(zhResult, equals('- 中文行 1'));

      final enResult = processChangelogContent(unbalancedContent, isChinese: false);
      expect(enResult.split('\n').length, equals(4));
      expect(enResult, isNot(contains('中文行 1')));
    });

    test('processChangelogContent falls back symmetrically when only one language exists', () {
      const englishOnly = '''
- Only english note 1
- Only english note 2
''';
      // Chinese user still gets the release notes instead of blank screen
      final zhFallback = processChangelogContent(englishOnly, isChinese: true);
      expect(zhFallback, contains('Only english note 1'));

      const chineseOnly = '''
- 仅中文特性 1
- 仅中文特性 2
''';
      // English user still gets the release notes instead of blank screen
      final enFallback = processChangelogContent(chineseOnly, isChinese: false);
      expect(enFallback, contains('仅中文特性 1'));
    });
  });

  group('ChangelogScreen widget rendering', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
    });

    testWidgets('renders ChangelogScreen on mobile and triggers onComplete', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: TestChangelogAssetBundle(),
              child: ChangelogScreen(
                lastVersion: '0.1.0-preview.4',
                currentVersion: '0.1.0-preview.5+5',
                onComplete: () {
                  completed = true;
                },
              ),
            ),
          ),
        ),
      );

      // Settle loading and markdown render
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text("What's New"), findsOneWidget);
      expect(find.text('v0.1.0-preview.5'), findsOneWidget);
      expect(find.text('Updated from 0.1.0-preview.4'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      final markdownFinder = find.byType(StyledMarkdown);
      expect(markdownFinder, findsOneWidget);
      final styledMarkdown = tester.widget<StyledMarkdown>(markdownFinder);
      expect(styledMarkdown.data, contains('Widget test new feature'));

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('renders ChangelogScreen on desktop in centered 820px card', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: TestChangelogAssetBundle(),
              child: ChangelogScreen(
                lastVersion: '0.1.0-preview.4',
                currentVersion: '0.1.0-preview.5+5',
                onComplete: () {
                  completed = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text("What's New"), findsOneWidget);
      expect(find.text('v0.1.0-preview.5'), findsOneWidget);
      expect(find.text('Updated from 0.1.0-preview.4'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Verify desktop ConstrainedBox with maxWidth: 820 is present
      final constrainedBoxFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox &&
            widget.constraints.maxWidth == 820 &&
            widget.constraints.maxHeight == 900,
      );
      expect(constrainedBoxFinder, findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('suppresses migration text when lastVersion equals currentVersion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: DefaultAssetBundle(
              bundle: TestChangelogAssetBundle(),
              child: ChangelogScreen(
                lastVersion: '0.1.0-preview.5',
                currentVersion: '0.1.0-preview.5+5',
                onComplete: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('v0.1.0-preview.5'), findsOneWidget);
      expect(find.textContaining('Updated from'), findsNothing);
    });

    testWidgets('renders ChangelogScreen.show as Dialog on desktop and closes via close button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool completed = false;

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: TestChangelogAssetBundle(),
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    ChangelogScreen.show(
                      context,
                      lastVersion: '0.1.0-preview.4',
                      currentVersion: '0.1.0-preview.5+5',
                      onComplete: () {
                        completed = true;
                      },
                    );
                  },
                  child: const Text('Open Changelog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open changelog dialog
      await tester.tap(find.text('Open Changelog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Should be displayed in a Dialog
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('v0.1.0-preview.5'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Close via close icon button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(completed, isTrue);
    });

    testWidgets('renders ChangelogScreen in isDialog: true mode without outer Scaffold AppBar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: DefaultAssetBundle(
            bundle: TestChangelogAssetBundle(),
            child: ChangelogScreen(
              lastVersion: '0.1.0-preview.4',
              currentVersion: '0.1.0-preview.5+5',
              isDialog: true,
              onComplete: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('v0.1.0-preview.5'), findsOneWidget);
      // Outer Scaffold AppBar should not be present in Dialog mode
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('Real assets/CHANGELOG.md integrity & anti-regression guard', () {
    test('assets/CHANGELOG.md contains a section header for current version in pubspec.yaml', () {
      final pubspecContent = File('pubspec.yaml').readAsStringSync();
      final versionMatch = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspecContent);
      expect(versionMatch, isNotNull, reason: 'pubspec.yaml must define a version');
      final currentVersion = versionMatch!.group(1)!;

      final changelogContent = File('assets/CHANGELOG.md').readAsStringSync();
      final headerPattern = RegExp(
        r'^##\s+\[?' + RegExp.escape(currentVersion) + r'(\]|\s|$)',
        multiLine: true,
      );
      expect(
        headerPattern.hasMatch(changelogContent),
        isTrue,
        reason: 'assets/CHANGELOG.md must contain a section header matching current version $currentVersion from pubspec.yaml',
      );
    });

    test('assets/CHANGELOG.md extracts current version cleanly without bleeding into earlier versions', () {
      final pubspecContent = File('pubspec.yaml').readAsStringSync();
      final versionMatch = RegExp(r'^version:\s*([^\s]+)', multiLine: true).firstMatch(pubspecContent);
      final currentVersion = versionMatch!.group(1)!;

      final changelogContent = File('assets/CHANGELOG.md').readAsStringSync();
      final extracted = extractVersionChangelog(changelogContent, currentVersion);

      // Must not be fallback default content
      expect(extracted, isNot(equals(defaultChangelogContent)));

      // Must contain preview.5 items
      expect(extracted, contains('Fix(changelog):'));
      expect(extracted, contains('重构更新日志解析器'));

      // Must stop before preview.4
      expect(extracted, isNot(contains('## [0.1.0-preview.4]')));
      expect(extracted, isNot(contains('addColumnIfNotExists')));
      expect(extracted, isNot(contains('数据库迁移幂等性加固')));

      // Bilingual separation verification on real asset
      final zhNotes = processChangelogContent(extracted, isChinese: true);
      final enNotes = processChangelogContent(extracted, isChinese: false);

      expect(zhNotes, contains('重构更新日志解析器'));
      expect(zhNotes, isNot(contains('Modernize Changelog parser')));

      expect(enNotes, contains('Modernize Changelog parser'));
      expect(enNotes, isNot(contains('重构更新日志解析器')));
    });

    test('assets/CHANGELOG.md historical preview versions are non-empty and properly delimited', () {
      final changelogContent = File('assets/CHANGELOG.md').readAsStringSync();
      final versionsToCheck = [
        '0.1.0-preview.5',
        '0.1.0-preview.4',
        '0.1.0-preview.3',
        '0.1.0-preview.2',
        '0.1.0-preview.1',
      ];

      for (final ver in versionsToCheck) {
        final extracted = extractVersionChangelog(changelogContent, ver);
        expect(extracted, isNotEmpty, reason: '$ver section must not be empty');
        expect(extracted, isNot(equals(defaultChangelogContent)), reason: '$ver must have its own section');
      }
    });
  });
}
