import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    documentPath = Platform.isWindows ? r'C:\Mock\Documents' : '/mock/documents';
    SharedPreferences.setMockInitialValues({
      'showBookTitleOnDefaultCover': true,
      'showAuthorOnDefaultCover': true,
    });
    await Prefs().initPrefs();
  });

  final testBook = Book(
    id: -1,
    title: 'Practical Electronics for Inventors, Fourth Edition (Paul Scherz Simon Monk) (z-library.sk, 1lib.sk, z-lib.sk)',
    coverPath: '',
    filePath: 'dummy.epub',
    lastReadPosition: '',
    readingPercentage: 0.0,
    author: 'Paul Scherz & Simon Monk',
    isDeleted: false,
    rating: 0.0,
    createTime: DateTime.now(),
    updateTime: DateTime.now(),
  );

  Widget buildCoverInBox(Book book, double width, double height) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: BookCover(book: book),
          ),
        ),
      ),
    );
  }

  group('BookCover responsive layout tests', () {
    testWidgets('renders cleanly without overflow in desktop wide landscape mode (1720 x 761)', (tester) async {
      await tester.pumpWidget(buildCoverInBox(testBook, 1720.3, 761.1));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BookCover), findsOneWidget);
    });

    testWidgets('renders cleanly without overflow in compact thumbnail mode (36 x 50)', (tester) async {
      await tester.pumpWidget(buildCoverInBox(testBook, 36.0, 50.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BookCover), findsOneWidget);
    });

    testWidgets('renders cleanly in standard bookshelf grid dimension (140 x 200)', (tester) async {
      await tester.pumpWidget(buildCoverInBox(testBook, 140.0, 200.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BookCover), findsOneWidget);
    });
  });
}
