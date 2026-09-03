import 'dart:convert';
import 'dart:io';

class SystemFontService {
  SystemFontService._();
  static final SystemFontService instance = SystemFontService._();

  List<String>? _cachedSystemFonts;

  /// Sets or clears cached system fonts (useful for tests or overriding).
  void setMockSystemFonts(List<String>? fonts) {
    _cachedSystemFonts = fonts != null ? deduplicateAndSort(fonts) : null;
  }

  /// Retrieves available system font family names asynchronously.
  Future<List<String>> getAvailableSystemFonts({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSystemFonts != null && _cachedSystemFonts!.isNotEmpty) {
      return _cachedSystemFonts!;
    }

    List<String> fonts = [];

    if (Platform.isWindows) {
      fonts = await _scanWindowsRegistryFonts();
    }

    if (fonts.isEmpty) {
      fonts = getFallbackSystemFonts();
    }

    _cachedSystemFonts = deduplicateAndSort(fonts);
    return _cachedSystemFonts!;
  }

  /// Scans Windows registry for installed fonts across both HKLM and HKCU.
  Future<List<String>> _scanWindowsRegistryFonts() async {
    final List<String> discovered = [];

    const keys = [
      r'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
      r'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
    ];

    for (final key in keys) {
      try {
        final result = await Process.run(
          'reg',
          ['query', key],
          stdoutEncoding: systemEncoding,
        );

        if (result.exitCode == 0 && result.stdout is String) {
          final parsed = parseRegistryFontOutput(result.stdout as String);
          discovered.addAll(parsed);
        }
      } catch (_) {
        // Fall through gracefully if reg command fails or is restricted
      }
    }

    return discovered;
  }

  /// Parses raw stdout from `reg query ...\Fonts`.
  static List<String> parseRegistryFontOutput(String stdout) {
    if (stdout.isEmpty) return [];

    final List<String> result = [];
    final lines = const LineSplitter().convert(stdout);

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('HKEY_') || trimmed.startsWith('ERROR:')) {
        continue;
      }

      // Reg query output format: <FontName>    <REG_TYPE>    <FileName>
      final regTypeIndex = trimmed.indexOf('REG_SZ');
      final regExpandIndex = trimmed.indexOf('REG_EXPAND_SZ');

      int splitIndex = -1;
      if (regTypeIndex != -1) {
        splitIndex = regTypeIndex;
      } else if (regExpandIndex != -1) {
        splitIndex = regExpandIndex;
      }

      if (splitIndex <= 0) continue;

      String rawName = trimmed.substring(0, splitIndex).trim();

      // Remove format qualifiers
      rawName = rawName
          .replaceAll(RegExp(r'\s*\((?:TrueType|OpenType|All fonts)\)', caseSensitive: false), '')
          .trim();

      // Split compound font names (e.g. "Microsoft YaHei & Microsoft YaHei UI")
      if (rawName.contains('&')) {
        final parts = rawName.split('&');
        for (final part in parts) {
          final clean = part.trim();
          if (clean.isNotEmpty) {
            result.add(clean);
          }
        }
      } else if (rawName.isNotEmpty) {
        result.add(rawName);
      }
    }

    return result;
  }

  /// Deduplicates and alphabetically sorts font names.
  static List<String> deduplicateAndSort(List<String> fontNames) {
    final seen = <String>{};
    final List<String> unique = [];

    for (final name in fontNames) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        unique.add(trimmed);
      }
    }

    unique.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return unique;
  }

  /// Curated fallback system fonts for platforms where registry scanning is not available.
  static List<String> getFallbackSystemFonts() {
    return [
      // Windows
      'Microsoft YaHei',
      'Microsoft YaHei UI',
      'SimSun',
      'NSimSun',
      'SimHei',
      'KaiTi',
      'FangSong',
      'Segoe UI',
      // macOS / iOS
      'PingFang SC',
      'PingFang TC',
      'PingFang HK',
      'Hiragino Sans GB',
      'Songti SC',
      'Kaiti SC',
      'Yuanti SC',
      // Android / Linux / Open Source
      'Noto Sans CJK SC',
      'Noto Serif CJK SC',
      'Source Han Sans SC',
      'Source Han Serif SC',
      'Droid Sans Fallback',
      'WenQuanYi Micro Hei',
      'WenQuanYi Zen Hei',
      'LXGW WenKai',
    ];
  }
}
