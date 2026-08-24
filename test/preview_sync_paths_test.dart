import 'dart:io';

import 'package:anx_reader/config/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview sync helper keeps every object in its own namespace', () {
    expect(AppIdentity.syncPath(), 'anx-reader-gx-preview');
    expect(
      AppIdentity.syncPath('/data/file/'),
      'anx-reader-gx-preview/data/file',
    );
    expect(
      AppIdentity.syncPath('database50.db'),
      'anx-reader-gx-preview/database50.db',
    );
  });

  test('active sync sources contain no legacy anx remote paths', () {
    const sourceFiles = <String>[
      'lib/providers/sync.dart',
      'lib/service/database_sync_manager.dart',
      'lib/service/sync/webdav_client.dart',
    ];
    final legacyPath = RegExp(r'''["']/??anx(?:/|["'])''');

    for (final sourceFile in sourceFiles) {
      final source = File(sourceFile).readAsStringSync();
      expect(
        legacyPath.hasMatch(source),
        isFalse,
        reason: '$sourceFile must use AppIdentity.syncPath().',
      );
    }
  });
}
