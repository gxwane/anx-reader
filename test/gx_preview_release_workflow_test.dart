import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workflow;

  setUpAll(() {
    workflow =
        File('.github/workflows/gx-preview-release.yaml').readAsStringSync();
  });

  test('release workflow supports tag and manual dispatch, validating Preview version and tag',
      () {
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('tags:'));
    expect(workflow, contains(r'gx-v${VERSION}'));
    expect(workflow, contains(r'^\d+\.\d+\.\d+-preview\.\d+$'));
  });

  test('Android artifacts are fork signed and have stable names', () {
    expect(workflow, contains('GX_ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('GX_ANDROID_KEYSTORE_PASSWORD'));
    expect(workflow, contains('GX_ANDROID_KEY_PASSWORD'));
    expect(workflow, contains('GX_ANDROID_KEY_ALIAS'));
    expect(
      workflow,
      contains(
        r'Anx-Reader-GX-Preview-android-${{ needs.validate.outputs.version }}-arm64-v8a.apk',
      ),
    );
    expect(
      workflow,
      contains(
        r'Anx-Reader-GX-Preview-android-${{ needs.validate.outputs.version }}-universal.apk',
      ),
    );
  });

  test('Windows installer is built and staged as a release asset', () {
    expect(workflow, contains('name: Build Windows installer'));
    expect(workflow, contains('build_windows_installer.ps1'));
    expect(
      workflow,
      contains(
        r'Anx-Reader-GX-Preview-windows-${{ needs.validate.outputs.version }}-setup.exe',
      ),
    );
    expect(workflow, contains('gx-preview-windows-assets'));
  });

  test('release is checksummed, marked prerelease, and fork owned', () {
    expect(workflow, contains('SHA256SUMS.txt'));
    expect(workflow, contains('upstream_base'));
    expect(workflow, contains('prerelease: true'));
    expect(workflow, isNot(contains('254a26d6-6c3a-4a55-9ca6-890d0d34deb1')));
    expect(workflow, isNot(contains('NOTIFICATION_URL')));
    expect(workflow, isNot(contains('anx.anxcye.com')));
    expect(
      workflow,
      contains('This is an unofficial, independently maintained Preview fork'),
    );
  });

  test('release governance and privacy policies are documented', () {
    final signing = File('docs/code-signing-policy.md').readAsStringSync();
    final privacy = File('docs/privacy-policy.md').readAsStringSync();

    expect(signing, contains('SignPath'));
    expect(signing, contains('Release manager'));
    expect(signing, contains('SignPath approver'));
    expect(signing, contains('Get-AuthenticodeSignature'));
    expect(signing, contains('unsigned bootstrap'));
    expect(signing, contains('SHA-256'));
    expect(privacy, contains('Anx Reader GX Preview'));
    expect(privacy, contains('WebDAV'));
    expect(privacy, contains('anx-reader-gx-preview'));
  });
}
