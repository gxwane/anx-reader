import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Intent Filter Specifications (Clean Craftsmanship)', () {
    late String manifest;
    late List<String> allIntentFilters;
    late List<String> actionViewFilters;
    late List<String> actionSendFilters;

    setUpAll(() {
      manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      allIntentFilters = RegExp(
        r'<intent-filter\b[^>]*>[\s\S]*?</intent-filter>',
      ).allMatches(manifest).map((m) => m.group(0)!).toList();

      actionViewFilters = allIntentFilters
          .where((f) => f.contains('android:name="android.intent.action.VIEW"'))
          .toList();
      actionSendFilters = allIntentFilters
          .where((f) => f.contains('android:name="android.intent.action.SEND"'))
          .toList();
    });

    test('Scenario 1: Android manifest must NOT contain wildcard "*/*" mimeType in intent filters', () {
      final wildcardMatches = RegExp(
        r'<data\b[^>]*android:mimeType="\*/\*"\s*/>',
      ).allMatches(manifest);

      expect(
        wildcardMatches,
        isEmpty,
        reason:
            'Wildcard "*/*" mimeType causes Anx Reader to intercept APK installations and unrelated file types.',
      );
    });

    test('Scenario 2: ACTION_VIEW must support explicit eBook MIME types in its dedicated MIME filter', () {
      final requiredMimes = [
        'application/epub+zip',
        'application/pdf',
        'text/plain',
        'application/x-mobipocket-ebook',
        'application/vnd.amazon.ebook',
        'application/x-fictionbook+xml',
      ];

      // Find the primary ACTION_VIEW filter for standard MIME types (without octet-stream)
      final mimeViewFilter = actionViewFilters.firstWhere(
        (f) => !f.contains('android:mimeType="application/octet-stream"') && f.contains('android:mimeType='),
        orElse: () => actionViewFilters.first,
      );

      for (final mime in requiredMimes) {
        expect(
          mimeViewFilter.contains('android:mimeType="$mime"'),
          isTrue,
          reason: 'Dedicated ACTION_VIEW MIME filter must explicitly support MIME type "$mime".',
        );
      }
    });

    test('Scenario 3: ACTION_VIEW must support explicit eBook file extensions with pathPattern', () {
      final requiredExtensions = [
        '.epub',
        '.EPUB',
        '.mobi',
        '.MOBI',
        '.azw3',
        '.AZW3',
        '.azw',
        '.AZW',
        '.fb2',
        '.FB2',
        '.txt',
        '.TXT',
        '.pdf',
        '.PDF',
      ];

      final pathViewFilter = actionViewFilters.firstWhere(
        (f) => f.contains('android:pathPattern=') && !f.contains('android:mimeType="application/octet-stream"'),
        orElse: () => actionViewFilters.first,
      );

      for (final ext in requiredExtensions) {
        final pattern = 'android:pathPattern=".*\\\\$ext"';
        expect(
          pathViewFilter.contains(pattern),
          isTrue,
          reason: 'ACTION_VIEW pathPattern filter must register extension "$ext".',
        );
      }
    });

    test('Scenario 4: ACTION_SEND and ACTION_SEND_MULTIPLE must not contain wildcard MIME', () {
      expect(actionSendFilters, isNotEmpty);
      for (final filter in actionSendFilters) {
        expect(
          filter.contains('android:mimeType="*/*"'),
          isFalse,
          reason: 'ACTION_SEND intent filter must not use wildcard "*/*".',
        );
      }
    });
  });
}
