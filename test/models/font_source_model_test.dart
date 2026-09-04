import 'package:anx_reader/models/font_source_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FontSourceModel Tests', () {
    test('official source defaults', () {
      expect(FontSourceModel.official.id, 'official');
      expect(FontSourceModel.official.name, 'Official Store');
      expect(FontSourceModel.official.manifestUrl,
          'https://fonts.anxcye.com/fonts-manifest.json');
      expect(FontSourceModel.official.isOfficial, isTrue);
    });

    test('serialization and deserialization roundtrip', () {
      const source = FontSourceModel(
        id: 'custom_source_1',
        name: 'Community Fonts',
        manifestUrl: 'https://example.com/fonts.json',
        isOfficial: false,
      );

      final jsonStr = source.toJson();
      final decoded = FontSourceModel.fromJson(jsonStr);

      expect(decoded.id, 'custom_source_1');
      expect(decoded.name, 'Community Fonts');
      expect(decoded.manifestUrl, 'https://example.com/fonts.json');
      expect(decoded.isOfficial, isFalse);
      expect(decoded, equals(source));
    });

    test('equality and hashCode contract', () {
      const a = FontSourceModel(
        id: 'test',
        name: 'Test',
        manifestUrl: 'https://test.com/manifest.json',
        isOfficial: false,
      );
      const b = FontSourceModel(
        id: 'test',
        name: 'Test',
        manifestUrl: 'https://test.com/manifest.json',
        isOfficial: false,
      );
      const c = FontSourceModel(
        id: 'test2',
        name: 'Test',
        manifestUrl: 'https://test.com/manifest.json',
        isOfficial: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
