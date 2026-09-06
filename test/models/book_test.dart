import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    documentPath = Platform.isWindows ? r'C:\Mock\Documents' : '/mock/documents';
  });

  group('Book model tests', () {
    test('isExternalPreview returns true when id <= 0 and false when id > 0', () {
      final previewBook = Book(
        id: -1,
        title: 'Preview',
        coverPath: '',
        filePath: 'mock.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );
      expect(previewBook.isExternalPreview, isTrue);

      final zeroIdBook = previewBook.copyWith(id: 0);
      expect(zeroIdBook.isExternalPreview, isTrue);

      final importedBook = previewBook.copyWith(id: 42);
      expect(importedBook.isExternalPreview, isFalse);
    });

    test('fileFullPath returns absolute path as-is when filePath is absolute', () {
      final absolutePath = Platform.isWindows
          ? r'D:\Books\ExternalNovel.epub'
          : '/Users/test/Documents/ExternalNovel.epub';

      final book = Book(
        id: -1,
        title: 'External Book',
        coverPath: '',
        filePath: absolutePath,
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      expect(book.fileFullPath, equals(absolutePath));
    });

    test('fileFullPath prepends documentPath when filePath is relative', () {
      const relativePath = 'file/imported_book.epub';
      final book = Book(
        id: 1,
        title: 'Imported Book',
        coverPath: 'cover/imported_book.png',
        filePath: relativePath,
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      expect(book.fileFullPath, equals(getBasePath(relativePath)));
      expect(book.coverFullPath, equals(getBasePath('cover/imported_book.png')));
    });
  });
}
