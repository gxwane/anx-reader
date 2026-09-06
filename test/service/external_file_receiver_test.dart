import 'dart:io';

import 'package:anx_reader/service/receive_file/external_file_receiver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('external_file_receiver_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ExternalFileReceiver unit tests', () {
    test('isSupportedBookFile validates supported and unsupported extensions', () {
      expect(ExternalFileReceiver.isSupportedBookFile('book.epub'), isTrue);
      expect(ExternalFileReceiver.isSupportedBookFile('book.EPUB'), isTrue);
      expect(ExternalFileReceiver.isSupportedBookFile('document.pdf'), isTrue);
      expect(ExternalFileReceiver.isSupportedBookFile('novel.mobi'), isTrue);
      expect(ExternalFileReceiver.isSupportedBookFile('kindle.azw3'), isTrue);
      expect(ExternalFileReceiver.isSupportedBookFile('story.fb2'), isTrue);
      expect(ExternalFileReceiver.isSupportedBookFile('notes.txt'), isTrue);

      expect(ExternalFileReceiver.isSupportedBookFile('app.exe'), isFalse);
      expect(ExternalFileReceiver.isSupportedBookFile('archive.zip'), isFalse);
      expect(ExternalFileReceiver.isSupportedBookFile('picture.png'), isFalse);
      expect(ExternalFileReceiver.isSupportedBookFile('word.docx'), isFalse);
    });

    test('cleanFilePathFromArgs handles flags, quotes, and non-existent files', () {
      final validFile = File('${tempDir.path}/valid_book.epub')..writeAsStringSync('dummy content');

      // Empty args
      expect(ExternalFileReceiver.cleanFilePathFromArgs([]), isNull);

      // Only flags
      expect(
        ExternalFileReceiver.cleanFilePathFromArgs([
          '--enable-dart-profiling',
          '-v',
          '--observatory-port=1234',
        ]),
        isNull,
      );

      // Non-existent file
      expect(
        ExternalFileReceiver.cleanFilePathFromArgs(['${tempDir.path}/non_existent.epub']),
        isNull,
      );

      // Existing file without quotes
      expect(
        ExternalFileReceiver.cleanFilePathFromArgs([validFile.path]),
        equals(validFile.path),
      );

      // Existing file wrapped in double quotes
      expect(
        ExternalFileReceiver.cleanFilePathFromArgs(['"${validFile.path}"']),
        equals(validFile.path),
      );

      // Existing file wrapped in single quotes
      expect(
        ExternalFileReceiver.cleanFilePathFromArgs(["'${validFile.path}'"]),
        equals(validFile.path),
      );

      // Flags before valid file
      expect(
        ExternalFileReceiver.cleanFilePathFromArgs([
          '--enable-asserts',
          '"${validFile.path}"',
        ]),
        equals(validFile.path),
      );
    });

    test('calculateFileMd5Stream computes correct stream hash', () async {
      final sampleFile = File('${tempDir.path}/test_hash.txt')..writeAsStringSync('Hello Anx Reader');
      final md5Hash = await ExternalFileReceiver.calculateFileMd5Stream(sampleFile);

      expect(md5Hash, isNotNull);
      expect(md5Hash!.length, equals(32));
      expect(md5Hash, equals('69781fcade66f5903348ca67c697dbd1'));
    });

    test('setInitialFilePathFromArgs manages pending startup file', () {
      final validFile = File('${tempDir.path}/startup.pdf')..writeAsStringSync('pdf content');

      ExternalFileReceiver.pendingStartupFilePath = null;
      ExternalFileReceiver.setInitialFilePathFromArgs(['--flag', '"${validFile.path}"']);
      expect(ExternalFileReceiver.pendingStartupFilePath, equals(validFile.path));

      // Re-set with invalid
      ExternalFileReceiver.pendingStartupFilePath = null;
      ExternalFileReceiver.setInitialFilePathFromArgs(['--only-flags']);
      expect(ExternalFileReceiver.pendingStartupFilePath, isNull);
    });

    test('clearLastHandled resets debounce state immediately', () {
      ExternalFileReceiver.clearLastHandled();
      // Calling clearLastHandled should ensure subsequent calls are unblocked
      expect(() => ExternalFileReceiver.clearLastHandled(), returnsNormally);
    });
  });
}
