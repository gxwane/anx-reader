import 'package:anx_reader/models/font_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FontModel System Font Entity & Contract', () {
    test('FontModel.systemFont creates immutable model with system: prefix', () {
      final model = FontModel.systemFont(familyName: 'Microsoft YaHei');

      expect(model.id, equals('system:Microsoft YaHei'));
      expect(model.name, equals('Microsoft YaHei'));
      expect(model.label, equals('Microsoft YaHei'));
      expect(model.source, equals(FontSource.systemFont));
      expect(model.path, isEmpty);
      expect(model.isDeletable, isFalse);
      expect(model.getWebUrl(8080), isEmpty,
          reason: 'System fonts must not generate HTTP URLs');
    });

    test('FontModel.systemFont accepts custom label', () {
      final model = FontModel.systemFont(
        familyName: 'Microsoft YaHei',
        label: '微软雅黑',
      );

      expect(model.id, equals('system:Microsoft YaHei'));
      expect(model.label, equals('微软雅黑'));
      expect(model.name, equals('Microsoft YaHei'));
    });

    test('FontModel serializes and deserializes system font correctly', () {
      final original = FontModel.systemFont(
        familyName: 'PingFang SC',
        label: '苹方',
      );

      final json = original.toJson();
      final restored = FontModel.fromJson(json);

      expect(restored.id, equals('system:PingFang SC'));
      expect(restored.name, equals('PingFang SC'));
      expect(restored.label, equals('苹方'));
      expect(restored.source, equals(FontSource.systemFont));
      expect(restored.isDeletable, isFalse);
    });
  });
}
