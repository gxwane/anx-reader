import 'package:anx_reader/service/font/system_font_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemFontService Cross-Platform Discovery & Parser', () {
    test('parseRegistryFontOutput correctly extracts and strips font family names', () {
      const mockRegOutput = '''
HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts
    Arial (TrueType)    REG_SZ    arial.ttf
    Microsoft YaHei & Microsoft YaHei UI (TrueType)    REG_SZ    msyh.ttc
    SimSun & NSimSun (TrueType)    REG_SZ    simsun.ttc
    Segoe UI (TrueType)    REG_SZ    segoeui.ttf
    Source Han Serif SC Regular (OpenType)    REG_SZ    SourceHanSerifSC-Regular.otf
    KaiTi (TrueType)    REG_SZ    simkai.ttf
''';

      final parsed = SystemFontService.parseRegistryFontOutput(mockRegOutput);

      expect(parsed, contains('Arial'));
      expect(parsed, contains('Microsoft YaHei'));
      expect(parsed, contains('Microsoft YaHei UI'));
      expect(parsed, contains('SimSun'));
      expect(parsed, contains('NSimSun'));
      expect(parsed, contains('Segoe UI'));
      expect(parsed, contains('Source Han Serif SC Regular'));
      expect(parsed, contains('KaiTi'));

      // Suffixes must be stripped
      for (final font in parsed) {
        expect(font.contains('(TrueType)'), isFalse);
        expect(font.contains('(OpenType)'), isFalse);
      }
    });

    test('parseRegistryFontOutput handles empty or error output gracefully', () {
      expect(SystemFontService.parseRegistryFontOutput(''), isEmpty);
      expect(SystemFontService.parseRegistryFontOutput('ERROR: The system was unable to find...'), isEmpty);
    });

    test('deduplicateAndSort filters out empty and duplicates', () {
      final input = [
        'Microsoft YaHei',
        'Arial',
        'Microsoft YaHei',
        '',
        '  ',
        'SimSun',
      ];

      final result = SystemFontService.deduplicateAndSort(input);

      expect(result.length, equals(3));
      expect(result, containsAll(['Arial', 'Microsoft YaHei', 'SimSun']));
    });

    test('getFallbackSystemFonts returns high-quality curated fonts', () {
      final fallback = SystemFontService.getFallbackSystemFonts();

      expect(fallback, isNotEmpty);
      expect(fallback.any((f) => f.contains('YaHei') || f.contains('PingFang') || f.contains('Sans')), isTrue);
    });

    test('getAvailableSystemFonts completes and returns non-empty list on host', () async {
      final fonts = await SystemFontService.instance.getAvailableSystemFonts();

      expect(fonts, isNotEmpty);
      // On Windows development machine, it should discover real system fonts
      expect(fonts.any((f) => f.isNotEmpty), isTrue);
    });
  });
}
