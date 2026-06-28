import 'package:anx_reader/models/book_note.dart';

class ExternalNoteRecord {
  const ExternalNoteRecord({
    required this.source,
    required this.content,
    required this.readerNote,
    required this.chapterIndex,
    required this.startOffset,
    required this.length,
    required this.color,
    required this.createTime,
  });

  final String source;
  final String content;
  final String? readerNote;
  final int chapterIndex;
  final int startOffset;
  final int length;
  final String color;
  final DateTime createTime;

  Map<String, dynamic> toResolveJson(int index) {
    return {
      'index': index,
      'content': content,
      'readerNote': readerNote,
      'chapterIndex': chapterIndex,
      'startOffset': startOffset,
      'length': length,
      'color': color,
      'createTime': createTime.toIso8601String(),
    };
  }
}

class ResolvedExternalNote {
  const ResolvedExternalNote({
    required this.index,
    required this.target,
    required this.chapter,
    required this.content,
    required this.readerNote,
    required this.color,
    required this.createTime,
  });

  final int index;
  final String target;
  final String chapter;
  final String content;
  final String? readerNote;
  final String color;
  final DateTime createTime;

  factory ResolvedExternalNote.fromJson(Map<dynamic, dynamic> json) {
    return ResolvedExternalNote(
      index: (json['index'] as num).toInt(),
      target: json['target']?.toString() ?? '',
      chapter: json['chapter']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      readerNote: json['readerNote']?.toString(),
      color: json['color']?.toString() ?? 'FFD700',
      createTime: DateTime.tryParse(json['createTime']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  BookNote toBookNote(int bookId) {
    return BookNote(
      bookId: bookId,
      content: content,
      cfi: target,
      chapter: chapter,
      type: 'highlight',
      color: color,
      readerNote: readerNote,
      createTime: createTime,
      updateTime: DateTime.now(),
    );
  }
}

class ExternalNoteImportReport {
  const ExternalNoteImportReport({
    required this.parsed,
    required this.resolved,
    required this.imported,
    required this.duplicates,
    required this.unresolved,
    required this.parseErrors,
  });

  final int parsed;
  final int resolved;
  final int imported;
  final int duplicates;
  final int unresolved;
  final int parseErrors;
}
