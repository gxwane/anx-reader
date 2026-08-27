import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('GX Preview project identity', () {
    test('uses an independent Android identity and version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final gradle = File('android/app/build.gradle').readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/anxcye/anx_reader/MainActivity.kt',
      ).readAsStringSync();
      final labels = <String>[
        File(
          'android/app/src/main/res/values/strings.xml',
        ).readAsStringSync(),
        File(
          'android/app/src/main/res/values-zh/strings.xml',
        ).readAsStringSync(),
      ];

      expect(pubspec, matches(RegExp(r'version:\s*0\.1\.0-preview\.\d+\+\d+')));
      expect(
        gradle,
        contains('applicationId "io.github.gxwane.anx_reader_gx_preview"'),
      );
      expect(
        activity,
        contains('io.github.gxwane.anx_reader_gx_preview/install_info'),
      );
      for (final label in labels) {
        expect(label, contains('Anx Reader GX Preview'));
      }
    });

    test('uses an independent Windows identity', () {
      final cmake = File('windows/CMakeLists.txt').readAsStringSync();
      final resources = File('windows/runner/Runner.rc').readAsStringSync();
      final main = File('windows/runner/main.cpp').readAsStringSync();
      final installer = File(
        'scripts/compile_windows_setup-inno.iss',
      ).readAsStringSync();
      final installerBuilder = File(
        'scripts/build_windows_installer.ps1',
      ).readAsStringSync();

      expect(cmake, contains('set(BINARY_NAME "anx_reader_gx_preview")'));
      expect(resources, contains('"CompanyName", "gxwane"'));
      expect(resources, contains('"ProductName", "Anx Reader GX Preview"'));
      expect(main, contains('L"Anx Reader GX Preview"'));
      expect(installer, contains('#define MyAppName "Anx Reader GX Preview"'));
      expect(
        installer,
        contains(
          '#define MyAppId "{{9DDF6922-4FE8-4AB4-9BD4-9E7C2E5038A1}}"',
        ),
      );
      expect(installerBuilder, contains(r'"/DStagingDir=$stagingDir"'));
      expect(
        installerBuilder,
        contains(r'"/DInstallerOutputDir=$installerOut"'),
      );
      expect(installerBuilder, contains(r'"/DMyAppVersion=$appVersion"'));
      expect(installerBuilder, contains(r'"/F$installerBaseName"'));
      expect(installerBuilder, isNot(contains(r'""$stagingDir""')));

      final dartMain = File('lib/main.dart').readAsStringSync();
      final windowValidator =
          File('lib/utils/window_position_validator.dart').readAsStringSync();

      expect(dartMain, contains('title: AppIdentity.displayName'));
      expect(
        windowValidator,
        contains('WindowManager.instance.setTitle(AppIdentity.displayName)'),
      );
    });

    test('centralizes fork-owned URLs and sync namespace', () {
      final identity = File('lib/config/app_identity.dart').readAsStringSync();

      expect(identity, contains("'Anx Reader GX Preview'"));
      expect(identity, contains("'https://github.com/gxwane/anx-reader'"));
      expect(identity, contains("'anx-reader-gx-preview'"));
    });

    test('routes help links to the repository that owns each document', () {
      final identity = File('lib/config/app_identity.dart').readAsStringSync();
      final about = File(
        'lib/widgets/settings/about.dart',
      ).readAsStringSync();
      final issueTemplate = File(
        '.github/ISSUE_TEMPLATE/bug-report.yaml',
      ).readAsStringSync();

      expect(
        identity,
        allOf(
          contains('static const String documentationUrl'),
          contains(r"'$repositoryUrl/tree/develop/docs'"),
        ),
      );
      expect(
        identity,
        allOf(
          contains('static const String troubleshootingUrl'),
          contains(
            r"'$repositoryUrl/blob/develop/docs/troubleshooting.md'",
          ),
        ),
      );
      expect(
        identity,
        contains("'https://anx.anxcye.com/docs'"),
      );
      expect(about, contains('AppIdentity.documentationUrl'));
      expect(
        about,
        isNot(
          contains(
            r"${AppIdentity.upstreamRepositoryUrl}/tree/develop/docs",
          ),
        ),
      );
      expect(
        issueTemplate,
        contains(
          'https://github.com/gxwane/anx-reader/blob/develop/docs/troubleshooting.md',
        ),
      );
      expect(
        issueTemplate,
        isNot(
            contains('Anxcye/anx-reader/blob/develop/docs/troubleshooting.md')),
      );

      const upstreamGuideFiles = <String>[
        'lib/page/settings_page/sync.dart',
        'lib/service/tts/openai_tts_backend.dart',
        'lib/service/tts/azure_tts_backend.dart',
        'lib/service/tts/aliyun/aliyun_tts_backend.dart',
        'lib/service/translate/google_api.dart',
        'lib/service/translate/microsoft_api.dart',
        'lib/service/translate/deepl.dart',
      ];
      for (final path in upstreamGuideFiles) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('AppIdentity.upstreamDocumentationUrl'),
          reason: '$path must explicitly use the upstream documentation root.',
        );
        expect(
          source,
          isNot(contains('https://anx.anxcye.com/docs')),
          reason: '$path must not hard-code the upstream documentation root.',
        );
      }
    });

    test('documents the fork status in README and About', () {
      final readme = File('README.md').readAsStringSync();
      final chineseReadme = File('README_zh.md').readAsStringSync();
      final about = File(
        'lib/widgets/settings/about.dart',
      ).readAsStringSync();

      expect(readme, contains('unofficial, independently maintained'));
      expect(chineseReadme, contains('非官方、独立维护'));
      expect(about, contains('aboutForkStatusTitle'));
      expect(about, contains('aboutForkStatusBody'));
    });

    test('keeps the original icon unchanged outside the GX corner badge', () {
      final original = img.decodePng(
        File('assets/icon/Anx-logo.png').readAsBytesSync(),
      )!;
      final preview = img.decodePng(
        File('assets/icon/Anx-logo-gx-preview.png').readAsBytesSync(),
      )!;

      expect(preview.width, original.width);
      expect(preview.height, original.height);

      var changedInsideBadge = 0;
      var changedOutsideBadge = 0;
      var orangePixels = 0;
      for (final pixel in preview) {
        final before = original.getPixel(pixel.x, pixel.y);
        final changed = before.r != pixel.r ||
            before.g != pixel.g ||
            before.b != pixel.b ||
            before.a != pixel.a;
        final insideBadge = pixel.x >= preview.width * 0.57 &&
            pixel.y >= preview.height * 0.18 &&
            pixel.y <= preview.height * 0.48;
        if (changed && insideBadge) changedInsideBadge++;
        if (changed && !insideBadge) changedOutsideBadge++;
        if (pixel.r > 180 && pixel.g < 150 && pixel.b < 120) {
          orangePixels++;
        }
      }

      expect(changedInsideBadge, greaterThan(1000));
      expect(changedOutsideBadge, 0);
      expect(orangePixels, greaterThan(1000));
    });

    test('emits readable Android and Windows GX icon resources', () {
      const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      const names = [
        'ic_launcher',
        'ic_launcher_round',
        'ic_launcher_foreground',
      ];
      for (final density in densities) {
        for (final name in names) {
          final icon = img.decodePng(
            File(
              'android/app/src/main/res/mipmap-$density/$name.png',
            ).readAsBytesSync(),
          );
          expect(icon, isNotNull, reason: '$density/$name.png must decode');
        }
      }

      final windowsIcon = img.IcoDecoder().decode(
        File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
      );
      expect(windowsIcon, isNotNull);
      expect(
        windowsIcon!.frames.map((frame) => frame.width),
        orderedEquals([16, 32, 48, 64, 128, 256]),
      );
    });
  });
}
