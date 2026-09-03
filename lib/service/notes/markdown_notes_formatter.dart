import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:intl/intl.dart';

/// Pure domain/service utility to format reading notes into standardized
/// Markdown documents with YAML Frontmatter, compatible with Obsidian,
/// Logseq, Notion, Dataview, and general PKM tools.
class MarkdownNotesFormatter {
  static const Set<String> _windowsReservedNames = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// Sanitizes a book title and optional author into a cross-platform safe filename (.md).
  ///
  /// - Format: `<title> - <author>.md` (or `<title>.md` if author is empty)
  /// - Strips invalid characters: `\ / : * ? " < > | \n \r \t`
  /// - Handles Windows reserved filenames (e.g., CON, NUL)
  /// - Trims trailing spaces and dots
  /// - Truncates base name to safe length (max 120 graphemes)
  static String sanitizeFileName(String title, {String? author}) {
    String cleanTitle = _cleanComponent(title);
    String cleanAuthor = author != null ? _cleanComponent(author) : '';

    String baseName;
    if (cleanTitle.isEmpty && cleanAuthor.isEmpty) {
      baseName = 'untitled';
    } else if (cleanAuthor.isEmpty) {
      baseName = cleanTitle;
    } else if (cleanTitle.isEmpty) {
      baseName = cleanAuthor;
    } else {
      baseName = '$cleanTitle - $cleanAuthor';
    }

    if (baseName.characters.length > 120) {
      baseName = baseName.characters.take(120).toString().trim();
    }

    // Strip trailing dots and spaces (invalid on Windows)
    baseName = baseName.replaceAll(RegExp(r'[\s\.]+$'), '');
    if (baseName.isEmpty) baseName = 'untitled';

    // Handle Windows reserved device names
    final upper = baseName.toUpperCase();
    if (_windowsReservedNames.contains(upper)) {
      baseName = '${baseName}_book';
    }

    return '$baseName.md';
  }

  static String _cleanComponent(String raw) {
    return raw
        .replaceAll(RegExp(r'[\r\n\t]'), ' ')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\s\.]+$'), '')
        .trim();
  }

  /// Formats a book and its active notes into a structured Markdown document.
  static String formatBookNotesToMarkdown(
    Book book,
    List<BookNote> notes, {
    DateTime? exportedAt,
  }) {
    final now = exportedAt ?? DateTime.now().toUtc();
    final activeNotes = notes
        .where((n) => !n.isDeleted)
        .toList();

    // Sort notes: chronologically by updateTime / id
    activeNotes.sort((a, b) => a.updateTime.compareTo(b.updateTime));

    final buffer = StringBuffer();
    final isoDate = now.toIso8601String();
    final formattedDate =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(now.toLocal());
    final percentageNum =
        double.parse((book.readingPercentage * 100).toStringAsFixed(1));

    // 1. YAML Frontmatter (Using jsonEncode for strictly valid YAML/JSON string escaping)
    buffer.writeln('---');
    buffer.writeln('type: "book-note"');
    buffer.writeln('title: ${jsonEncode(book.title)}');
    buffer.writeln('author: ${jsonEncode(book.author)}');
    buffer.writeln('book_id: ${book.id}');
    buffer.writeln('file_md5: ${jsonEncode(book.md5)}');
    buffer.writeln('reading_status: ${jsonEncode(book.status.name)}');
    buffer.writeln('reading_percentage: $percentageNum');
    buffer.writeln('total_notes: ${activeNotes.length}');
    buffer.writeln('last_updated: "$isoDate"');
    buffer.writeln('tags:');
    buffer.writeln('  - anx-reader');
    buffer.writeln('  - book-notes');
    buffer.writeln('---\n');

    // 2. Book Header
    buffer.writeln('# ${book.title}\n');
    buffer.writeln('> **作者**：${book.author.isNotEmpty ? book.author : '未知'}  ');
    buffer.writeln(
        '> **阅读进度**：$percentageNum%  ');
    buffer.writeln('> **更新时间**：$formattedDate  ');
    buffer.writeln('> **笔记总数**：${activeNotes.length} 条  \n');
    buffer.writeln('---\n');

    if (activeNotes.isEmpty) {
      buffer.writeln('*暂无划线或批注笔记*\n');
      return buffer.toString();
    }

    // 3. Group by Chapter (Aggregated by chapter key so non-contiguous notes don't duplicate headings)
    final chapterGroups = _groupNotesByChapter(activeNotes);

    for (final group in chapterGroups) {
      final chapterTitle = group.chapter.trim().isNotEmpty
          ? group.chapter.trim()
          : '正文';
      buffer.writeln('## $chapterTitle\n');

      for (final note in group.notes) {
        // Highlight content quote block
        if (note.content.isNotEmpty) {
          final quoteLines = note.content.trim().split('\n');
          for (final line in quoteLines) {
            buffer.writeln('> $line');
          }
          buffer.writeln();
        }

        // Reader annotation / comment (with multiline indentation support)
        if (note.readerNote != null && note.readerNote!.trim().isNotEmpty) {
          final formattedNote =
              note.readerNote!.trim().replaceAll('\n', '\n  ');
          buffer.writeln('- **批注**：$formattedNote');
        }

        // Metadata line (type, color, timestamp)
        final typeLabel = _getNoteTypeLabel(note.type);
        final colorStr = note.color.isNotEmpty ? '#${note.color}' : '';
        final noteDate = DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(note.updateTime.toLocal());

        final metaParts = <String>[];
        if (typeLabel.isNotEmpty) metaParts.add('类型：$typeLabel');
        if (colorStr.isNotEmpty) metaParts.add('颜色：$colorStr');
        metaParts.add('时间：$noteDate');

        buffer.writeln('- *${metaParts.join(" ｜ ")}*\n');
      }

      buffer.writeln('---\n');
    }

    return buffer.toString();
  }

  static String _getNoteTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'highlight':
        return '划线高亮';
      case 'underline':
        return '下划线';
      case 'bookmark':
        return '书签';
      default:
        return type;
    }
  }

  static List<_ChapterGroup> _groupNotesByChapter(List<BookNote> notes) {
    if (notes.isEmpty) return const [];

    final map = <String, List<BookNote>>{};
    for (final note in notes) {
      final key = note.chapter.trim().isNotEmpty ? note.chapter.trim() : '正文';
      map.putIfAbsent(key, () => []).add(note);
    }

    return map.entries
        .map((e) => _ChapterGroup(e.key, e.value))
        .toList(growable: false);
  }
}

class _ChapterGroup {
  final String chapter;
  final List<BookNote> notes;

  _ChapterGroup(this.chapter, this.notes);
}
