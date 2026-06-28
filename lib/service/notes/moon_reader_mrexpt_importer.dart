import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:anx_reader/constants/note_annotations.dart';
import 'package:anx_reader/models/external_note_import.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:charset/charset.dart';

class MoonReaderMrexptImportResult {
  const MoonReaderMrexptImportResult({
    required this.records,
    required this.parseErrors,
    this.sourceTitle,
    this.sourcePath,
  });

  final List<ExternalNoteRecord> records;
  final int parseErrors;
  final String? sourceTitle;
  final String? sourcePath;
}

class MoonReaderMrexptImporter {
  Future<MoonReaderMrexptImportResult> parse(File file) async {
    final text = await _readText(file);
    final blocks = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n#\n'))
        .map((block) => block.trim())
        .where((block) => block.isNotEmpty)
        .toList();

    AnxLog.info(
      'MoonReader mrexpt import: file=${file.path}, blocks=${blocks.length}',
    );

    final records = <ExternalNoteRecord>[];
    var parseErrors = 0;
    String? sourceTitle;
    String? sourcePath;

    for (final block in blocks) {
      if (!_looksLikeRecordBlock(block)) {
        continue;
      }
      final metadata = _parseMetadata(block);
      sourceTitle ??= metadata.title;
      sourcePath ??= metadata.path;
      final record = _parseBlock(block);
      if (record == null) {
        parseErrors++;
      } else {
        records.add(record);
      }
    }

    for (var i = 0; i < records.length && i < 5; i++) {
      final record = records[i];
      AnxLog.info(
        'MoonReader mrexpt record[$i]: chapterIndex=${record.chapterIndex}, '
        'startOffset=${record.startOffset}, length=${record.length}, '
        'contentLength=${record.content.length}, hasReaderNote=${record.readerNote?.isNotEmpty ?? false}, '
        'content="${_preview(record.content)}"',
      );
    }

    AnxLog.info(
      'MoonReader mrexpt import result: records=${records.length}, parseErrors=$parseErrors, '
      'sourceTitle="${sourceTitle ?? ''}", sourcePath="${sourcePath ?? ''}"',
    );

    return MoonReaderMrexptImportResult(
      records: records,
      parseErrors: parseErrors,
      sourceTitle: sourceTitle,
      sourcePath: sourcePath,
    );
  }

  Future<String> _readText(File file) async {
    final bytes = await file.readAsBytes();
    AnxLog.info('MoonReader mrexpt import: bytes=${bytes.length}');
    final decoders = <String, String Function(List<int>)>{
      'utf8': utf8.decode,
      'gbk': gbk.decode,
      'latin1': latin1.decode,
    };

    for (final entry in decoders.entries) {
      try {
        final text = entry.value(bytes);
        AnxLog.info('MoonReader mrexpt import: decoded with ${entry.key}');
        return text;
      } catch (error) {
        AnxLog.warning(
          'MoonReader mrexpt import: failed decoding with ${entry.key}: $error',
        );
      }
    }

    throw const FormatException('MoonReader mrexpt import: failed to decode');
  }

  String _preview(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 80 ? '${compact.substring(0, 80)}...' : compact;
  }

  bool _looksLikeRecordBlock(String block) {
    final lines = block.replaceAll('\r\n', '\n').split('\n');
    return lines.length >= 9 && int.tryParse(lines.first.trim()) != null;
  }

  ({String? title, String? path}) _parseMetadata(String block) {
    final lines = block.replaceAll('\r\n', '\n').split('\n');
    final title = lines.length > 1 ? lines[1].trim() : '';
    final path = lines.length > 2 ? lines[2].trim() : '';
    return (
      title: title.isEmpty ? null : title,
      path: path.isEmpty ? null : path,
    );
  }

  ExternalNoteRecord? _parseBlock(String block) {
    final lines = block.replaceAll('\r\n', '\n').split('\n');
    if (lines.length < 13) return null;

    final recordStart = int.tryParse(lines[0].trim());
    if (recordStart == null) return null;

    final chapterIndex = int.tryParse(lines[4].trim());
    final startOffset = int.tryParse(lines[6].trim());
    final length = int.tryParse(lines[7].trim());
    final moonColor = int.tryParse(lines[8].trim());
    final timestamp = int.tryParse(lines[9].trim());
    if (chapterIndex == null ||
        startOffset == null ||
        length == null ||
        moonColor == null ||
        timestamp == null) {
      return null;
    }

    final trailing = lines.skip(10).toList();
    while (trailing.isNotEmpty && trailing.last.trim() == '0') {
      trailing.removeLast();
    }
    if (trailing.isEmpty) return null;

    final content = trailing.removeLast().trim();
    final readerNote = trailing.join('\n').trim();
    if (content.isEmpty) return null;

    return ExternalNoteRecord(
      source: 'moon_reader',
      content: content,
      readerNote: readerNote.isEmpty ? null : readerNote,
      chapterIndex: chapterIndex,
      startOffset: startOffset,
      length: length,
      color: _mapColor(moonColor),
      createTime: DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
  }

  String _mapColor(int moonColor) {
    final normalized = moonColor.toUnsigned(32);
    final rgb = normalized & 0x00ffffff;
    final r = (rgb >> 16) & 0xff;
    final g = (rgb >> 8) & 0xff;
    final b = rgb & 0xff;

    String best = notesColors.first;
    var bestDistance = double.infinity;
    for (final color in notesColors) {
      final value = int.parse(color, radix: 16);
      final cr = (value >> 16) & 0xff;
      final cg = (value >> 8) & 0xff;
      final cb = value & 0xff;
      final distance =
          math.pow(r - cr, 2) + math.pow(g - cg, 2) + math.pow(b - cb, 2);
      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        best = color;
      }
    }
    return best;
  }
}
