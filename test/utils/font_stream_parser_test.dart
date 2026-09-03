import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/utils/font_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenType Stream Parser (Memory-efficient & Multi-format)', () {
    final fontFile = File('assets/fonts/SourceHanSerifSC-Regular.otf');

    test('parses OTF metadata correctly without loading full file', () async {
      expect(fontFile.existsSync(), isTrue, reason: 'Test bundled font must exist');

      final metadata = await parseFontMetadata(fontFile);
      expect(metadata, isNotNull);
      expect(metadata!.postscriptName, equals('SourceHanSerifCN-Regular'));
      expect(
        metadata.familyName,
        anyOf(contains('Source Han Serif'), contains('思源宋体')),
      );
      expect(metadata.styleOrSubfamily, equals('Regular'));
      expect(metadata.fileSize, fontFile.lengthSync());
    });

    test('efficient random-access I/O reads less than 64KB from large font file', () async {
      final totalFileBytes = fontFile.lengthSync();
      expect(totalFileBytes, greaterThan(1024 * 1024),
          reason: 'SourceHanSerif is over 1MB');

      // Verify with benchmarked stream parser reading footprint
      final bytesRead = await measureParserReadBytes(fontFile);
      expect(bytesRead, lessThan(64 * 1024),
          reason: 'Must read only headers and name table, strictly < 64KB (saved >99% I/O)');
    });

    test('gracefully handles non-font or corrupted file', () async {
      final tempFile = File('${Directory.systemTemp.path}/test_invalid_font.otf');
      await tempFile.writeAsBytes([0, 1, 2, 3, 4, 5, 6, 7]);

      try {
        final metadata = await parseFontMetadata(tempFile);
        expect(metadata, isNull);
      } finally {
        if (tempFile.existsSync()) {
          await tempFile.delete();
        }
      }
    });

    test('gracefully rejects corrupted font with excessive nameTableLength', () async {
      final tempFile = File('${Directory.systemTemp.path}/test_overflow_font.otf');
      final bytes = Uint8List(12 + 16);
      final data = ByteData.sublistView(bytes);
      data.setUint32(0, 0x4F54544F); // 'OTTO'
      data.setUint16(4, 1); // 1 table
      // Table entry: 'name'
      bytes[12] = 0x6E; bytes[13] = 0x61; bytes[14] = 0x6D; bytes[15] = 0x65;
      data.setUint32(16, 0); // checksum
      data.setUint32(20, 28); // offset
      data.setUint32(24, 0x7FFFFFFF); // length: 2GB (overflow attempt)
      await tempFile.writeAsBytes(bytes);

      try {
        final metadata = await parseFontMetadata(tempFile);
        expect(metadata, isNull);
      } finally {
        if (tempFile.existsSync()) {
          await tempFile.delete();
        }
      }
    });
  });
}
