import 'dart:io';

import 'package:anx_reader/service/book_metadata_extractor.dart';
import 'package:archive/archive_io.dart';
import 'package:test/test.dart';

void main() {
  test('extracts EPUB metadata from OPF without WebView', () async {
    final dir = await Directory.systemTemp.createTemp('metadata_test_');
    final file = File('${dir.path}/sample.epub');
    final encoder = ZipFileEncoder()..create(file.path);
    encoder.addArchiveFile(ArchiveFile.string(
      'META-INF/container.xml',
      '''<?xml version="1.0"?>
<container>
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"/>
  </rootfiles>
</container>''',
    ));
    encoder.addArchiveFile(ArchiveFile.string(
      'OEBPS/content.opf',
      '''<?xml version="1.0"?>
<package>
  <metadata>
    <dc:title>Test Book</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:description>Test Description</dc:description>
  </metadata>
</package>''',
    ));
    encoder.close();

    final metadata = await BookMetadataExtractor().extract(file);

    expect(metadata.title, 'Test Book');
    expect(metadata.author, 'Test Author');
    expect(metadata.description, 'Test Description');
    expect(metadata.cover, isEmpty);
    expect(metadata.fallback, isFalse);

    await dir.delete(recursive: true);
  });

  test('falls back to filename when metadata cannot be extracted', () async {
    final dir = await Directory.systemTemp.createTemp('metadata_test_');
    final file = File('${dir.path}/fallback.epub');
    await file.writeAsString('not a zip');

    final metadata = await BookMetadataExtractor().extract(file);

    expect(metadata.title, 'fallback');
    expect(metadata.author, 'Unknown');
    expect(metadata.description, isEmpty);
    expect(metadata.cover, isEmpty);
    expect(metadata.fallback, isTrue);

    await dir.delete(recursive: true);
  });
}
