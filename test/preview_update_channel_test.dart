import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview update action never contacts upstream update services', () {
    final updateSource = File('lib/utils/check_update.dart').readAsStringSync();
    final environment = File('lib/utils/env_var.dart').readAsStringSync();

    expect(updateSource, isNot(contains('api.anx.anxcye.com')));
    expect(updateSource, isNot(contains('Anxcye/anx-reader/releases')));
    expect(updateSource, contains('AppIdentity.releasesUrl'));
    expect(environment, contains('enableAutomaticUpdateCheck => false'));
  });

  test('about screen distinguishes the fork from upstream', () {
    final about = File('lib/widgets/settings/about.dart').readAsStringSync();

    expect(about, contains('AppIdentity.displayName'));
    expect(about, contains('AppIdentity.repositoryUrl'));
    expect(about, contains('AppIdentity.upstreamRepositoryUrl'));
    expect(about, isNot(contains('anx.anxcye.com/privacy')));
    expect(about, isNot(contains('anx.anxcye.com/terms')));
  });

  test('localized app names identify the GX Preview', () {
    final arbFiles = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((file) => RegExp(r'app_.*\.arb$').hasMatch(file.path));

    for (final file in arbFiles) {
      final source = file.readAsStringSync();
      final messages = jsonDecode(source) as Map<String, dynamic>;
      expect(
        messages['appName'],
        'Anx Reader GX Preview',
        reason: '${file.path} must expose the Preview product name.',
      );
      expect(
        messages['appAbout'],
        contains('Anx Reader GX Preview'),
        reason: '${file.path} must identify the Preview in About text.',
      );
    }
  });

  test('imagegen Preview icon masters are stored in the project', () {
    expect(File('assets/icon/Anx-logo-gx-preview.png').existsSync(), isTrue);
    expect(File('assets/icon/Anx-logo-gx-preview-foreground.png').existsSync(),
        isTrue);
  });
}
