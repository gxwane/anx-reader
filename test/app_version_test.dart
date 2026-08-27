import 'package:anx_reader/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion parsing and comparison', () {
    test('parses basic semver and prefixes', () {
      final v1 = AppVersion.parse('0.1.0');
      expect(v1.major, 0);
      expect(v1.minor, 1);
      expect(v1.patch, 0);
      expect(v1.isPreRelease, isFalse);

      final v2 = AppVersion.parse('gx-v0.1.0-preview.1+1');
      expect(v2.major, 0);
      expect(v2.minor, 1);
      expect(v2.patch, 0);
      expect(v2.isPreRelease, isTrue);
      expect(v2.preRelease, ['preview', '1']);
      expect(v2.build, '1');

      final v3 = AppVersion.parse('v1.2.3');
      expect(v3.major, 1);
      expect(v3.minor, 2);
      expect(v3.patch, 3);
      expect(v3.isPreRelease, isFalse);
    });

    test('compares preview versions correctly', () {
      final pre1 = AppVersion.parse('gx-v0.1.0-preview.1');
      final pre2 = AppVersion.parse('gx-v0.1.0-preview.2');
      final pre10 = AppVersion.parse('gx-v0.1.0-preview.10');
      final stable = AppVersion.parse('0.1.0');
      final nextPre = AppVersion.parse('0.1.1-preview.1');
      final nextStable = AppVersion.parse('0.1.1');

      expect(pre2 > pre1, isTrue);
      expect(pre10 > pre2, isTrue);
      // Stable 0.1.0 is newer than preview.1/preview.2
      expect(stable > pre1, isTrue);
      expect(stable > pre10, isTrue);

      // Next preview 0.1.1-preview.1 is newer than stable 0.1.0
      expect(nextPre > stable, isTrue);
      // Next stable 0.1.1 is newer than next preview
      expect(nextStable > nextPre, isTrue);

      // Equality
      expect(AppVersion.parse('v0.1.0') == AppVersion.parse('0.1.0'), isTrue);
      expect(AppVersion.parse('gx-v0.1.0-preview.1+1') == AppVersion.parse('0.1.0-preview.1+2'), isTrue);
    });
  });
}
