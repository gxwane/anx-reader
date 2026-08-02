import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android MainActivity always reuses a single recent task', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainActivity = RegExp(
      r'<activity\b(?=[^>]*android:name="\.MainActivity")[^>]*>',
      multiLine: true,
    ).firstMatch(manifest);

    expect(
      mainActivity,
      isNotNull,
      reason: 'AndroidManifest.xml must declare .MainActivity.',
    );

    final declaration = mainActivity!.group(0)!;
    expect(
      declaration,
      contains('android:launchMode="singleTask"'),
      reason: 'External intents must reuse the existing Anx task.',
    );
    expect(
      declaration,
      contains('android:documentLaunchMode="never"'),
      reason: 'Document intents must not create another recent task.',
    );
  });
}
