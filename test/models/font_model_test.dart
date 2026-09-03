import 'package:anx_reader/models/font_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FontModel Domain Entity & Backward Compatibility', () {
    test('creates FontModel with modern schema and round-trips via JSON', () {
      final model = FontModel(
        id: 'postscript:SourceHanSerifSC-Regular',
        label: '思源宋体',
        name: 'Source Han Serif SC',
        path: 'SourceHanSerifSC-Regular.otf',
        source: FontSource.localCustom,
        postscriptName: 'SourceHanSerifSC-Regular',
        fileSize: 10485760,
        isDeletable: true,
      );

      final jsonStr = model.toJson();
      final decoded = FontModel.fromJson(jsonStr);

      expect(decoded.id, 'postscript:SourceHanSerifSC-Regular');
      expect(decoded.label, '思源宋体');
      expect(decoded.name, 'Source Han Serif SC');
      expect(decoded.source, FontSource.localCustom);
      expect(decoded.postscriptName, 'SourceHanSerifSC-Regular');
      expect(decoded.fileSize, 10485760);
      expect(decoded.isDeletable, true);
    });

    test('seamlessly migrates legacy JSON without id and converts customFont0', () {
      // Legacy JSON format saved by older app versions in Prefs().font
      const legacyJson = '''
      {
        "label": "My Custom Font",
        "name": "customFont0",
        "path": "custom_font.ttf"
      }
      ''';

      final model = FontModel.fromJson(legacyJson);

      expect(model.label, 'My Custom Font');
      expect(model.id, isNotEmpty, reason: 'Must generate a stable ID for legacy JSON');
      expect(model.id, contains('custom_font.ttf'));
      expect(model.source, FontSource.localCustom);
      expect(model.isDeletable, true);
    });

    test('correctly maps preset and bundled sources', () {
      final bookPreset = FontModel.book();
      expect(bookPreset.id, 'preset:book');
      expect(bookPreset.source, FontSource.book);
      expect(bookPreset.isDeletable, false);

      final systemUiPreset = FontModel.systemUi();
      expect(systemUiPreset.id, 'preset:system');
      expect(systemUiPreset.source, FontSource.systemUi);
      expect(systemUiPreset.isDeletable, false);
    });
  });
}
