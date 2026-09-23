import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/widgets/bookshelf/book_opened_folder.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControlledBookList extends BookList {
  ControlledBookList(this.pending);

  final List<Completer<void>> pending;

  @override
  Future<List<List<Book>>> build() async => [];

  @override
  Future<void> dissolveGroup(List<Book> books) {
    final completion = Completer<void>();
    pending.add(completion);
    return completion.future;
  }
}

class LocalSyncStatus extends SyncStatus {
  @override
  Future<SyncStatusModel> build() async => const SyncStatusModel(
        localOnly: [],
        remoteOnly: [],
        both: [],
        nonExistent: [],
        downloading: [],
        uploading: [],
      );
}

void main() {
  late ControlledBookList notifier;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    notifier = ControlledBookList([]);
  });

  Future<void> openFolder(WidgetTester tester,
      {List<Book> books = const []}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookListProvider
            .overrideWith(() => ControlledBookList(notifier.pending)),
        syncStatusProvider.overrideWith(LocalSyncStatus.new),
      ],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => BookOpenedFolder(
                              books: books, groupName: 'Folder')),
                      child: const Text('Open'),
                    ))),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('dissolution waits, blocks duplicates and closes only on success',
      (tester) async {
    await openFolder(tester);
    await tester.tap(find.text('Dissolve'));
    await tester.pumpAndSettle();
    expect(find.byType(BookOpenedFolder), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Dissolve'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Dissolve'));
    expect(notifier.pending, hasLength(1));
    notifier.pending.single.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BookOpenedFolder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure keeps the dialog and allows a successful retry',
      (tester) async {
    await openFolder(tester);
    await tester.tap(find.text('Dissolve'));
    await tester.pump();
    notifier.pending.single.completeError(StateError('database write failed'));
    await tester.pumpAndSettle();
    expect(find.byType(BookOpenedFolder), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Dissolve'));
    await tester.pump();
    expect(find.text('Failed'), findsNothing);
    expect(notifier.pending, hasLength(2));
    notifier.pending.last.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BookOpenedFolder), findsNothing);
  });

  testWidgets('pending dissolution disables editing for a populated folder',
      (tester) async {
    final book = Book.mock().copyWith(
      groupId: 5,
      coverPath:
          '${Directory.systemTemp.path}/anx-folder-test-missing-cover.png',
      filePath:
          '${Directory.systemTemp.path}/anx-folder-test-missing-book.epub',
    );
    await openFolder(tester, books: [book]);
    expect(find.text('Mock Book'), findsWidgets);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.remove_circle), findsOneWidget);
    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Dissolve'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byType(BookItem), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    for (final button
        in tester.widgetList<IconButton>(find.byType(IconButton))) {
      expect(button.onPressed, isNull);
    }
    notifier.pending.single.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BookOpenedFolder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion does not pop a newer route', (tester) async {
    await openFolder(tester);
    await tester.tap(find.text('Dissolve'));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('New route')),
    )));
    await tester.pumpAndSettle();
    notifier.pending.single.complete();
    await tester.pumpAndSettle();
    expect(find.text('New route'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BookOpenedFolder), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    testWidgets('completion after dialog dismissal is safe (failure=$fail)',
        (tester) async {
      await openFolder(tester);
      await tester.tap(find.text('Dissolve'));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      if (fail) {
        notifier.pending.single.completeError(StateError('late failure'));
      } else {
        notifier.pending.single.complete();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Open'), findsOneWidget);
    });
  }
}
