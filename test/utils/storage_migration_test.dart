import 'dart:io';

import 'package:anx_reader/utils/get_path/storage_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anx_storage_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // isAnxLibraryDirectory
  // ---------------------------------------------------------------------------
  group('isAnxLibraryDirectory', () {
    test(
      'GIVEN directory contains databases/ subfolder, THEN returns true',
      () async {
        final dir = Directory(p.join(tempDir.path, 'lib_with_db'));
        await dir.create();
        await Directory(p.join(dir.path, 'databases')).create();

        expect(isAnxLibraryDirectory(dir.path), isTrue);
      },
    );

    test(
      'GIVEN directory contains file/ subfolder, THEN returns true',
      () async {
        final dir = Directory(p.join(tempDir.path, 'lib_with_file'));
        await dir.create();
        await Directory(p.join(dir.path, 'file')).create();

        expect(isAnxLibraryDirectory(dir.path), isTrue);
      },
    );

    test(
      'GIVEN directory is empty, THEN returns false',
      () async {
        final dir = Directory(p.join(tempDir.path, 'empty_dir'));
        await dir.create();

        expect(isAnxLibraryDirectory(dir.path), isFalse);
      },
    );

    test(
      'GIVEN directory contains only random files (not Anx structure), THEN returns false',
      () async {
        final dir = Directory(p.join(tempDir.path, 'random_dir'));
        await dir.create();
        await File(p.join(dir.path, 'foo.txt')).writeAsString('hello');

        expect(isAnxLibraryDirectory(dir.path), isFalse);
      },
    );

    test(
      'GIVEN directory does not exist, THEN returns false',
      () {
        expect(isAnxLibraryDirectory('/nonexistent/path/xyz'), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // performStorageMigration
  // ---------------------------------------------------------------------------
  group('performStorageMigration', () {
    test(
      'GIVEN source has a file already present in dest with same size, '
      'WHEN migrating, THEN succeeds without throwing',
      () async {
        final srcDir = Directory(p.join(tempDir.path, 'src'));
        final dstDir = Directory(p.join(tempDir.path, 'dst'));
        await srcDir.create();
        await dstDir.create();

        final srcFileDir = Directory(p.join(srcDir.path, 'file'));
        await srcFileDir.create();
        final srcBook = File(p.join(srcFileDir.path, 'book.epub'));
        await srcBook.writeAsBytes(List.filled(100, 0x42));

        final dstFileDir = Directory(p.join(dstDir.path, 'file'));
        await dstFileDir.create();
        final dstBook = File(p.join(dstFileDir.path, 'book.epub'));
        await dstBook.writeAsBytes(List.filled(100, 0x42));

        final result = await performStorageMigration(
          sourcePath: srcDir.path,
          destinationPath: dstDir.path,
        );

        expect(result, isTrue);
        expect(dstBook.existsSync(), isTrue);
        expect(await dstBook.length(), equals(100));
      },
    );

    test(
      'GIVEN source has a file that dest does not have, '
      'WHEN migrating, THEN file appears in dest',
      () async {
        final srcDir = Directory(p.join(tempDir.path, 'src2'));
        final dstDir = Directory(p.join(tempDir.path, 'dst2'));
        await srcDir.create();
        await dstDir.create();

        final srcFileDir = Directory(p.join(srcDir.path, 'file'));
        await srcFileDir.create();
        await File(p.join(srcFileDir.path, 'novel.epub'))
            .writeAsBytes(List.filled(200, 0x41));

        final result = await performStorageMigration(
          sourcePath: srcDir.path,
          destinationPath: dstDir.path,
        );

        expect(result, isTrue);
        expect(
          File(p.join(dstDir.path, 'file', 'novel.epub')).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'GIVEN source directory does not exist, '
      'WHEN migrating, THEN returns true (nothing to migrate)',
      () async {
        final srcDir = Directory(p.join(tempDir.path, 'src_none'));
        final dstDir = Directory(p.join(tempDir.path, 'dst_none'));
        await dstDir.create();

        final result = await performStorageMigration(
          sourcePath: srcDir.path,
          destinationPath: dstDir.path,
        );

        expect(result, isTrue);
      },
    );

    test(
      'GIVEN successful migration, THEN source data directories are removed',
      () async {
        final srcDir = Directory(p.join(tempDir.path, 'src3'));
        final dstDir = Directory(p.join(tempDir.path, 'dst3'));
        await srcDir.create();
        await dstDir.create();

        final srcFileDir = Directory(p.join(srcDir.path, 'file'));
        await srcFileDir.create();
        await File(p.join(srcFileDir.path, 'a.epub'))
            .writeAsBytes(List.filled(50, 0x10));

        await performStorageMigration(
          sourcePath: srcDir.path,
          destinationPath: dstDir.path,
        );

        expect(srcFileDir.existsSync(), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // isDirectoryEmpty
  // ---------------------------------------------------------------------------
  group('isDirectoryEmpty', () {
    test('empty dir returns true', () async {
      final dir = Directory(p.join(tempDir.path, 'empty'));
      await dir.create();
      expect(await isDirectoryEmpty(dir.path), isTrue);
    });

    test('non-empty dir returns false', () async {
      final dir = Directory(p.join(tempDir.path, 'notempty'));
      await dir.create();
      await File(p.join(dir.path, 'x.txt')).writeAsString('x');
      expect(await isDirectoryEmpty(dir.path), isFalse);
    });

    test('non-existent dir returns true', () async {
      expect(await isDirectoryEmpty('/nonexistent/abc/xyz'), isTrue);
    });
  });
}
