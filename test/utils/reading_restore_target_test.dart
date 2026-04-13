import 'package:anx_reader/utils/reading_restore_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading restore target', () {
    test('encodes fraction payload with clamped value', () {
      final encoded = encodeReadingRestoreTargetFromFraction(1.2);
      final decoded = decodeReadingRestoreTarget(encoded);

      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['fraction'], 1.0);
    });

    test('keeps legacy cfi string values', () {
      const legacyCfi = 'epubcfi(/6/2!/4/2/6)';

      expect(
        decodeReadingRestoreTarget(legacyCfi, fallbackFraction: 0.42),
        legacyCfi,
      );
    });

    test('parses structured fraction payloads', () {
      final decoded = decodeReadingRestoreTarget('{"fraction": -0.25}');

      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['fraction'], 0.0);
    });

    test('falls back to reading percentage when persisted target is absent',
        () {
      final decoded = decodeReadingRestoreTarget(
        '',
        fallbackFraction: 0.42,
      );

      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['fraction'], 0.42);
    });
  });
}
