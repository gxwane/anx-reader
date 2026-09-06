import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/bookshelf_selection_provider.dart';
import 'package:anx_reader/widgets/bookshelf/bookshelf_batch_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBookList extends BookList {
  FakeBookList(this._books);
  final List<List<Book>> _books;

  @override
  Future<List<List<Book>>> build() async => _books;
}

class FakeSelectionNotifier extends BookshelfSelectionNotifier {
  FakeSelectionNotifier(this._initial);
  final BookshelfSelectionState _initial;

  @override
  BookshelfSelectionState build() => _initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testBooks = [
    Book(
      id: 1,
      title: 'Three Body Problem',
      coverPath: 'cover1.jpg',
      filePath: 'file1.epub',
      lastReadPosition: '',
      readingPercentage: 0.1,
      author: 'Liu Cixin',
      isDeleted: false,
      rating: 5.0,
      createTime: DateTime(2025, 1, 1),
      updateTime: DateTime(2025, 1, 1),
      status: ReadingStatus.reading,
    ),
    Book(
      id: 2,
      title: 'The Dark Forest',
      coverPath: 'cover2.jpg',
      filePath: 'file2.epub',
      lastReadPosition: '',
      readingPercentage: 0.0,
      author: 'Liu Cixin',
      isDeleted: false,
      rating: 5.0,
      createTime: DateTime(2025, 1, 2),
      updateTime: DateTime(2025, 1, 2),
      status: ReadingStatus.unread,
    ),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Widget buildTestBar({
    required List<List<Book>> books,
    BookshelfSelectionState? selectionState,
  }) {
    return ProviderScope(
      overrides: [
        bookListProvider.overrideWith(() => FakeBookList(books)),
        if (selectionState != null)
          bookshelfSelectionNotifierProvider
              .overrideWith(() => FakeSelectionNotifier(selectionState)),
      ],
      child: const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(
          body: BookshelfBatchActionBar(),
        ),
      ),
    );
  }

  testWidgets(
      'Renders all 4 action buttons with disabled state when nothing selected',
      (tester) async {
    await tester.pumpWidget(
      buildTestBar(
        books: [
          [testBooks[0]],
          [testBooks[1]],
        ],
        selectionState: const BookshelfSelectionState(
          isSelectionMode: true,
          selectedBookIds: {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Change Status'), findsOneWidget);
    expect(find.text('Move to Group'), findsOneWidget);
    expect(find.text('Release Space'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(opacities.length, 4);
    for (final op in opacities) {
      expect(op.opacity, 0.38);
    }
  });

  testWidgets('Action buttons are active when 1 or more books selected',
      (tester) async {
    await tester.pumpWidget(
      buildTestBar(
        books: [
          [testBooks[0]],
          [testBooks[1]],
        ],
        selectionState: const BookshelfSelectionState(
          isSelectionMode: true,
          selectedBookIds: {1},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(opacities.length, 4);
    for (final op in opacities) {
      expect(op.opacity, 1.0);
    }
  });

  testWidgets('Tapping Change Status opens bottom sheet with 4 status options',
      (tester) async {
    await tester.pumpWidget(
      buildTestBar(
        books: [
          [testBooks[0]],
          [testBooks[1]],
        ],
        selectionState: const BookshelfSelectionState(
          isSelectionMode: true,
          selectedBookIds: {1, 2},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change Status'));
    await tester.pumpAndSettle();

    expect(find.text('Unread'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Abandoned'), findsOneWidget);
  });

  testWidgets('Tapping Delete opens confirmation dialog with notice',
      (tester) async {
    await tester.pumpWidget(
      buildTestBar(
        books: [
          [testBooks[0]],
          [testBooks[1]],
        ],
        selectionState: const BookshelfSelectionState(
          isSelectionMode: true,
          selectedBookIds: {1, 2},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete 2 selected books?'), findsOneWidget);
    expect(
      find.text(
        'Local book files will be removed, but notes and reading statistics are kept safely.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
  });
}
