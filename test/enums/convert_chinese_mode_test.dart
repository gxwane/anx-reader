import 'package:anx_reader/enums/convert_chinese_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConvertChineseMode Tests', () {
    test('GIVEN standard mode names, WHEN parsing, THEN returns matching enum', () {
      expect(getConvertChineseMode('none'), ConvertChineseMode.none);
      expect(getConvertChineseMode('s2t'), ConvertChineseMode.s2t);
      expect(getConvertChineseMode('t2s'), ConvertChineseMode.t2s);
      expect(getConvertChineseMode('s2tw'), ConvertChineseMode.s2tw);
      expect(getConvertChineseMode('s2hk'), ConvertChineseMode.s2hk);
    });

    test('GIVEN null or unknown mode names, WHEN parsing, THEN safely falls back to none', () {
      expect(getConvertChineseMode(null), ConvertChineseMode.none);
      expect(getConvertChineseMode(''), ConvertChineseMode.none);
      expect(getConvertChineseMode('unknown_future_mode'), ConvertChineseMode.none);
    });
  });
}
