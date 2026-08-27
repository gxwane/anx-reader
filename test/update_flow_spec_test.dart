import 'package:anx_reader/enums/update_channel.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/utils/check_update.dart';
import 'package:anx_reader/widgets/update/update_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget createTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('Gherkin Spec Verification: Update Flow & Channels', () {
    test('Scenario: SemVer comparison handles preview vs stable edge cases', () {
      final stable010 = AppVersion.parse('0.1.0');
      final preview010 = AppVersion.parse('0.1.0-preview.1');
      final preview011 = AppVersion.parse('0.1.1-preview.1');
      final stable011 = AppVersion.parse('0.1.1');

      // Edge case 1: 0.1.0-preview.1 is less than 0.1.0 (no downgrade prompt)
      expect(preview010 > stable010, isFalse);
      expect(stable010 > preview010, isTrue);

      // Edge case 2: Stable 0.1.0 can upgrade to newer preview 0.1.1-preview.1
      expect(preview011 > stable010, isTrue);

      // Edge case 3: Preview 0.1.1-preview.1 can upgrade to final stable 0.1.1
      expect(stable011 > preview011, isTrue);
    });

    testWidgets(
        'Scenario: Preview update dialog displays preview badge and warning banner with backup button',
        (WidgetTester tester) async {
      final previewRelease = ReleaseInfo(
        tagName: 'gx-v0.1.1-preview.1',
        version: AppVersion.parse('0.1.1-preview.1'),
        isPrerelease: true,
        title: 'Anx Reader GX Preview 0.1.1-preview.1',
        body: '### Features\n- Experimental feature',
        htmlUrl: 'https://github.com/gxwane/anx-reader/releases',
        assets: [
          const ReleaseAsset(
            name: 'Anx-Reader-GX-Preview-android-0.1.1-preview.1-arm64-v8a.apk',
            downloadUrl: 'https://example.com/test.apk',
            size: 15 * 1024 * 1024,
          )
        ],
      );

      await tester.pumpWidget(
        createTestApp(
          UpdateDialog(
            releaseInfo: previewRelease,
            currentVersion: '0.1.0',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert Preview badge is present
      expect(find.text('测试预览版'), findsOneWidget);

      // Assert Warning banner is present
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining('测试预览版本'), findsOneWidget);

      // Assert Backup button is present
      expect(find.text('前往备份'), findsOneWidget);
      expect(find.byIcon(Icons.backup_outlined), findsOneWidget);

      // Assert version comparison text
      expect(find.textContaining('0.1.0'), findsWidgets);
      expect(find.textContaining('0.1.1-preview.1'), findsWidgets);
    });

    testWidgets(
        'Scenario: Stable update dialog does NOT display warning banner or backup button',
        (WidgetTester tester) async {
      final stableRelease = ReleaseInfo(
        tagName: 'v0.1.1',
        version: AppVersion.parse('0.1.1'),
        isPrerelease: false,
        title: 'Anx Reader GX Preview 0.1.1',
        body: '### Stable Release Notes',
        htmlUrl: 'https://github.com/gxwane/anx-reader/releases',
        assets: [
          const ReleaseAsset(
            name: 'Anx-Reader-GX-Preview-windows-0.1.1-setup.exe',
            downloadUrl: 'https://example.com/setup.exe',
            size: 20 * 1024 * 1024,
          )
        ],
      );

      await tester.pumpWidget(
        createTestApp(
          UpdateDialog(
            releaseInfo: stableRelease,
            currentVersion: '0.1.0',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert Preview badge and warning banner are NOT rendered
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.text('前往备份'), findsNothing);
      expect(find.text('测试预览版'), findsNothing);

      // Assert normal update UI elements
      expect(find.textContaining('0.1.1'), findsWidgets);
    });

    test('Scenario: UpdateChannel enum round-trip serialization and defaults', () {
      expect(UpdateChannel.fromCode('stable'), UpdateChannel.stable);
      expect(UpdateChannel.fromCode('preview'), UpdateChannel.preview);
      // Fallback default
      expect(UpdateChannel.fromCode('unknown'), UpdateChannel.preview);
      expect(UpdateChannel.fromCode(null), UpdateChannel.preview);
    });

    test('Scenario: GitHub API requests contain compliant User-Agent and headers', () {
      expect(githubHeaders['Accept'], 'application/vnd.github+json');
      expect(githubHeaders['User-Agent'], 'AnxReader-GX-Preview');
      expect(githubHeaders['X-GitHub-Api-Version'], '2022-11-28');
    });

    test('Scenario: isRateLimitError correctly detects 403 status code and messages', () {
      final dio403 = DioException(
        requestOptions: RequestOptions(path: 'https://api.github.com/releases'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://api.github.com/releases'),
          statusCode: 403,
        ),
      );
      final dio404 = DioException(
        requestOptions: RequestOptions(path: 'https://api.github.com/releases'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://api.github.com/releases'),
          statusCode: 404,
        ),
      );
      final dioMsgRate = DioException(
        requestOptions: RequestOptions(path: 'https://api.github.com/releases'),
        message: 'API rate limit exceeded',
      );

      expect(isRateLimitError(dio403), isTrue);
      expect(isRateLimitError(dioMsgRate), isTrue);
      expect(isRateLimitError(dio404), isFalse);
      expect(isRateLimitError(Exception('generic network failure')), isFalse);
    });

    testWidgets(
        'Scenario: showRateLimitDialog displays clear notice and direct GitHub link',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showRateLimitDialog(context),
              child: const Text('Trigger Rate Limit'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trigger Rate Limit'));
      await tester.pumpAndSettle();

      // Assert dialog title and message
      expect(find.text('检查更新提示'), findsOneWidget);
      expect(find.textContaining('GitHub API 访问频率受限'), findsOneWidget);

      // Assert buttons
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('通过 GitHub'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });
  });
}

