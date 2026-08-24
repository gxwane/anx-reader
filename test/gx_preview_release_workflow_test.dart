import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workflow;

  setUpAll(() {
    workflow =
        File('.github/workflows/gx-preview-release.yaml').readAsStringSync();
  });

  test('release workflow is manual and validates the Preview version and tag',
      () {
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains('push:')));
    expect(workflow, contains('windows_bootstrap:'));
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
        r'Anx-Reader-GX-Preview-android-${{ inputs.version }}-arm64-v8a.apk',
      ),
    );
    expect(
      workflow,
      contains(
        r'Anx-Reader-GX-Preview-android-${{ inputs.version }}-universal.apk',
      ),
    );
  });

  test('Windows bootstrap and SignPath paths are mutually gated', () {
    expect(workflow, contains("inputs.windows_bootstrap == true"));
    expect(workflow, contains("inputs.windows_bootstrap == false"));
    expect(workflow, contains('GX_SIGNPATH_API_TOKEN'));
    expect(workflow, contains('GX_SIGNPATH_ORGANIZATION_ID'));
    expect(workflow, contains('GX_SIGNPATH_PROJECT_SLUG'));
    expect(workflow, contains('GX_SIGNPATH_SIGNING_POLICY_SLUG'));
    expect(workflow, contains('GX_SIGNPATH_ARTIFACT_CONFIGURATION_SLUG'));
    expect(
      workflow,
      contains('signpath/github-action-submit-signing-request@v2'),
    );
    expect(workflow, contains('Get-AuthenticodeSignature'));
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
