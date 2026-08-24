import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/page/home_page/settings_page.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'golden_test_helper.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupGoldenComparator(Uri.parse('test/golden/settings_page_golden_test.dart'), tolerance: 0.01);
    await loadGoldenTestFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Anx Reader GX Preview',
      packageName: 'com.anxcye.anx_reader.gxpreview',
      version: '0.1.0-preview.1',
      buildNumber: '1',
      buildSignature: '',
    );
    await Prefs().initPrefs();
  });

  testWidgets('SettingsPage golden snapshot and layout check', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('en'),
              theme: colorSchema(Prefs(), context, Brightness.light),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                body: RepaintBoundary(
                  key: repaintKey,
                  child: const SettingsPage(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 1. 验证艺术大字 Logo 与 GX PREVIEW 徽标
    expect(find.text('Anx'), findsOneWidget);
    expect(find.text('GX PREVIEW'), findsOneWidget);

    // 2. 使用官方 matchesGoldenFile 生成并比对像素快照
    await expectLater(
      find.byKey(repaintKey),
      matchesGoldenFile('goldens/settings_page.png'),
    );
  });
}
