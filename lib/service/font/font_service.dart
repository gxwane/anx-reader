import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/utils/font_parser.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class FontService {
  FontService._();
  static final FontService instance = FontService._();

  static final Set<String> _loadedFlutterFonts = {};

  static const Set<String> supportedExtensions = {
    'ttf',
    'otf',
    'ttc',
    'woff2',
  };

  static const Set<String> bundledFontFiles = {
    'SourceHanSerifSC-Regular.otf',
    'SourceHanSerifSC-Bold.otf',
  };

  Directory get fontDirectory => getFontDir();

  /// Scans the local font directory asynchronously using random-access stream parsing.
  Future<List<FontModel>> scanLocalFonts() async {
    final dir = fontDirectory;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return [];
    }

    final List<FontModel> result = [];
    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is! File) continue;

        final ext = entity.path.split('.').last.toLowerCase();
        if (!supportedExtensions.contains(ext)) continue;

        final fileName = entity.uri.pathSegments.last;
        final metadata = await parseFontMetadata(entity);

        final label = metadata?.familyName ?? fileName.split('.').first;
        final psName = metadata?.postscriptName;
        final id = psName != null && psName.isNotEmpty
            ? 'postscript:$psName'
            : 'file:$fileName';

        final isBundled = bundledFontFiles.contains(fileName);

        result.add(FontModel(
          id: id,
          label: label,
          name: metadata?.familyName ?? fileName.split('.').first,
          path: fileName,
          source: isBundled ? FontSource.bundled : FontSource.localCustom,
          postscriptName: psName,
          fileSize: metadata?.fileSize ?? await entity.length(),
          isDeletable: !isBundled,
        ));
      }
    } catch (_) {
      // Gracefully return discovered fonts if scanning encounters an error
    }

    return result;
  }

  /// Picks and imports font files from disk with complete asynchronous copy.
  Future<int> importFonts() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions.toList(),
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      return 0;
    }

    final dir = fontDirectory;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    int count = 0;
    for (final file in result.files) {
      if (file.path == null) continue;
      try {
        final sourceFile = File(file.path!);
        if (!await sourceFile.exists()) continue;

        final targetPath = '${dir.path}/${file.name}';
        await sourceFile.copy(targetPath);
        count++;
      } catch (_) {
        // Continue copying remaining files even if one fails
      }
    }

    return count;
  }

  /// Safely deletes a custom font file and resets active preferences if needed.
  Future<bool> deleteFont(FontModel font) async {
    if (!font.isDeletable || bundledFontFiles.contains(font.litePath)) {
      return false;
    }

    bool deleted = false;
    try {
      final file = File('${fontDirectory.path}/${font.litePath}');
      if (await file.exists()) {
        await file.delete();
        deleted = true;
      }
    } catch (_) {
      return false;
    }

    if (!deleted) return false;

    // Reset active preferences if deleted font was in use
    try {
      if (Prefs().font.id == font.id) {
        Prefs().font = FontModel.book();
      }

      if (Prefs().excerptShareFont.id == font.id) {
        Prefs().excerptShareFont = FontModel.bundled(
          label: 'Source Han Serif',
          name: 'SourceHanSerif',
          path: 'SourceHanSerifSC-Regular.otf',
          postscriptName: 'SourceHanSerifCN-Regular',
        );
      }
    } catch (_) {
      // Preferences might not be initialized in isolated unit tests
    }

    return true;
  }

  /// JIT on-demand loading of a single font into the Flutter Engine (e.g. for ExcerptShareCard).
  /// Eliminates the need to load all fonts into heap memory on startup.
  Future<void> ensureFlutterFontLoaded(FontModel font) async {
    if (_loadedFlutterFonts.contains(font.id)) return;
    if (font.source == FontSource.book ||
        font.source == FontSource.systemUi ||
        font.source == FontSource.systemFont) {
      return;
    }

    try {
      final file = File('${fontDirectory.path}/${font.litePath}');
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      final fontLoader = FontLoader(font.name);
      fontLoader.addFont(Future.value(bytes.buffer.asByteData()));
      await fontLoader.load();
      _loadedFlutterFonts.add(font.id);
    } catch (_) {
      // Prevent crash if font loading fails
    }
  }
}
