import 'dart:io';

import 'package:anx_reader/service/notes/moon_reader_mrexpt_importer.dart';
import 'package:charset/charset.dart';
import 'package:test/test.dart';

const _bookTitle = '\u80a0\u5b50\u7684\u5c0f\u5fc3\u601d';
const _readerNote = '\u8bfb\u8005\u7b14\u8bb0';
const _content = '\u4e00\u4e2a\u6210\u5e74\u4eba\u6bcf\u5c0f\u65f6'
    '\u6240\u9700\u8981\u7684\u80fd\u91cf\u4ec5\u548c'
    '\u4e00\u53ea100\u74e6\u7684\u7535\u706f\u6ce1\u4e00\u6837\u591a\u3002';

String _sample({
  required String readerNote,
  required String content,
  int style = 0,
}) {
  return '''
0
indent:true
trim:false
#
20
$_bookTitle
/sdcard/Books/MoonReader/attachments/sample.epub
/sdcard/books/moonreader/attachments/sample.epub
4
0
384
${content.length}
1996532479
1668086678240

$readerNote
$content
0
0
$style
''';
}

void main() {
  test('parses Moon Reader UTF-8 records with reader notes', () async {
    final dir = await Directory.systemTemp.createTemp('mrexpt_test_');
    final file = File('${dir.path}/sample.mrexpt');
    await file
        .writeAsString(_sample(readerNote: _readerNote, content: _content));

    final result = await MoonReaderMrexptImporter().parse(file);

    expect(result.records, hasLength(1));
    expect(result.parseErrors, 0);
    expect(result.sourceTitle, _bookTitle);
    expect(
        result.sourcePath, '/sdcard/Books/MoonReader/attachments/sample.epub');
    expect(result.records.first.chapterIndex, 4);
    expect(result.records.first.startOffset, 384);
    expect(result.records.first.length, _content.length);
    expect(result.records.first.readerNote, _readerNote);
    expect(result.records.first.content, _content);

    await dir.delete(recursive: true);
  });

  test('parses Moon Reader GBK records', () async {
    final dir = await Directory.systemTemp.createTemp('mrexpt_test_');
    final file = File('${dir.path}/sample.mrexpt');
    await file.writeAsBytes(
      gbk.encode(_sample(readerNote: '', content: _content)),
    );

    final result = await MoonReaderMrexptImporter().parse(file);

    expect(result.records, hasLength(1));
    expect(result.parseErrors, 0);
    expect(result.sourceTitle, _bookTitle);
    expect(
        result.sourcePath, '/sdcard/Books/MoonReader/attachments/sample.epub');
    expect(result.records.first.readerNote, isNull);
    expect(result.records.first.content, _content);

    await dir.delete(recursive: true);
  });

  test('parses Moon Reader highlight records (style=1) without reader note',
      () async {
    final dir = await Directory.systemTemp.createTemp('mrexpt_test_');
    final file = File('${dir.path}/sample.mrexpt');
    await file.writeAsString(
        _sample(readerNote: '', content: _content, style: 1));

    final result = await MoonReaderMrexptImporter().parse(file);

    expect(result.records, hasLength(1));
    expect(result.parseErrors, 0);
    expect(result.records.first.readerNote, isNull);
    expect(result.records.first.content, _content);

    await dir.delete(recursive: true);
  });

  test('parses Moon Reader highlight records (style=1) with reader note',
      () async {
    final dir = await Directory.systemTemp.createTemp('mrexpt_test_');
    final file = File('${dir.path}/sample.mrexpt');
    await file.writeAsString(
        _sample(readerNote: _readerNote, content: _content, style: 1));

    final result = await MoonReaderMrexptImporter().parse(file);

    expect(result.records, hasLength(1));
    expect(result.parseErrors, 0);
    expect(result.records.first.readerNote, _readerNote);
    expect(result.records.first.content, _content);

    await dir.delete(recursive: true);
  });
}
