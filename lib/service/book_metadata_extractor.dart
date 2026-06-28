import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

class ExtractedBookMetadata {
  const ExtractedBookMetadata({
    required this.title,
    required this.author,
    required this.description,
    required this.cover,
    required this.fallback,
  });

  final String title;
  final String author;
  final String description;
  final String cover;
  final bool fallback;
}

class BookMetadataExtractor {
  Future<ExtractedBookMetadata> extract(File file) async {
    final extension = path.extension(file.path).toLowerCase();
    if (extension == '.epub') {
      return _extractEpub(file);
    }

    return _fallback(file);
  }

  Future<ExtractedBookMetadata> _extractEpub(File file) async {
    try {
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final container = _findTextFile(archive, 'META-INF/container.xml');
      final opfPath = _firstMatch(
        container,
        RegExp(r'''full-path\s*=\s*["']([^"']+)["']'''),
      );
      if (opfPath == null || opfPath.isEmpty) {
        return _fallback(file);
      }

      final opf = _findTextFile(archive, opfPath);
      final title = _xmlText(opf, 'title');
      final author = _xmlText(opf, 'creator');
      final description = _xmlText(opf, 'description');
      final cover = _extractCover(archive, opf, opfPath);

      return ExtractedBookMetadata(
        title: title?.trim().isNotEmpty == true
            ? title!.trim()
            : _fallbackTitle(file),
        author: author?.trim().isNotEmpty == true ? author!.trim() : 'Unknown',
        description: description?.trim() ?? '',
        cover: cover ?? '',
        fallback: title?.trim().isNotEmpty != true,
      );
    } catch (_) {
      return _fallback(file);
    }
  }

  ExtractedBookMetadata _fallback(File file) {
    return ExtractedBookMetadata(
      title: _fallbackTitle(file),
      author: 'Unknown',
      description: '',
      cover: '',
      fallback: true,
    );
  }

  String _fallbackTitle(File file) => path.basenameWithoutExtension(file.path);

  String _findTextFile(Archive archive, String name) {
    final normalizedName = name.replaceAll('\\', '/');
    final file = archive.files.firstWhere(
      (entry) => entry.name.replaceAll('\\', '/') == normalizedName,
      orElse: () => throw StateError('EPUB entry not found: $name'),
    );
    return utf8.decode(_bytes(file.content), allowMalformed: true);
  }

  String? _extractCover(Archive archive, String opf, String opfPath) {
    final coverId = _firstMatch(
      opf,
      RegExp(
          r'''<meta[^>]+name\s*=\s*["']cover["'][^>]+content\s*=\s*["']([^"']+)["']''',
          caseSensitive: false),
    );
    if (coverId == null) return null;

    final itemPattern = RegExp(
      '''<item[^>]+id\\s*=\\s*["']${RegExp.escape(coverId)}["'][^>]+>''',
      caseSensitive: false,
    );
    final item = itemPattern.firstMatch(opf)?.group(0);
    final href = item == null
        ? null
        : _firstMatch(item, RegExp(r'''href\s*=\s*["']([^"']+)["']'''));
    if (href == null || href.isEmpty) return null;

    final opfDir = path.posix.dirname(opfPath.replaceAll('\\', '/'));
    final coverPath = path.posix.normalize(path.posix.join(opfDir, href));
    final file = archive.files
        .where((entry) => entry.name.replaceAll('\\', '/') == coverPath)
        .firstOrNull;
    if (file == null) return null;

    final bytes = _bytes(file.content);
    final mediaType = _coverMediaType(coverPath);
    return 'data:$mediaType;base64,${base64.encode(bytes)}';
  }

  String? _xmlText(String xml, String tagName) {
    final match = RegExp(
      '<(?:[^:>]+:)?$tagName\\b[^>]*>([\\s\\S]*?)</(?:[^:>]+:)?$tagName>',
      caseSensitive: false,
    ).firstMatch(xml);
    final raw = match?.group(1);
    if (raw == null) return null;
    return _decodeXml(raw.replaceAll(RegExp(r'<[^>]+>'), '').trim());
  }

  String? _firstMatch(String text, RegExp pattern) =>
      pattern.firstMatch(text)?.group(1);

  Uint8List _bytes(dynamic content) {
    if (content is Uint8List) return content;
    if (content is List<int>) return Uint8List.fromList(content);
    return Uint8List(0);
  }

  String _decodeXml(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  String _coverMediaType(String filePath) {
    switch (path.extension(filePath).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}
