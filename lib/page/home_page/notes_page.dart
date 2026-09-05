import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_notes_page.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/providers/notes_page_current_book.dart';
import 'package:anx_reader/providers/notes_statistics.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/utils/date/relative_time_formatter.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/book_notes/notes_import_flow.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/common/app_scrollbar.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/highlight_digit.dart';
import 'package:anx_reader/widgets/tips/notes_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (widget.controller == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 600) {
            return Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      notesStatistic(),
                      _searchBar(),
                      bookNotesList(false),
                    ],
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                const Expanded(
                  flex: 2,
                  child: NotesDetail(),
                ),
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                notesStatistic(),
                _searchBar(),
                bookNotesList(true),
              ],
            );
          }
        },
      ),
    );
  }

  Widget notesStatistic() {
    final notesStats = ref.watch(notesStatisticsProvider);

    TextStyle digitStyle = const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
    );
    TextStyle textStyle =
        const TextStyle(fontSize: 18, fontFamily: 'SourceHanSerif');

    return notesStats.when(
      data: (data) {
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        highlightDigit(
                          context,
                          L10n.of(context)
                              .notesNotesAcross(data['numberOfNotes']!),
                          textStyle,
                          digitStyle,
                        ),
                        highlightDigit(
                          context,
                          L10n.of(context).notesBooks(data['numberOfBooks']!),
                          textStyle,
                          digitStyle,
                        ),
                      ]),
                ),
                IconButton(
                  tooltip: L10n.of(context).notesPageImport,
                  icon: const Icon(Icons.note_add_outlined),
                  onPressed: () {
                    importMoonReaderNotesWithBookPicker(
                      context: context,
                      ref: ref,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: L10n.of(context).startTypingToSearch,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchTerm.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget bookNotesList(bool isMobile) {
    final bookIdAndNotes = ref.watch(bookIdAndNotesProvider);

    return bookIdAndNotes.when(
      data: (data) {
        final filteredData = _searchTerm.isEmpty
            ? data
            : data
                .where((item) => (item['book'] as Book)
                    .title
                    .toLowerCase()
                    .contains(_searchTerm.toLowerCase()))
                .toList();
        if (data.isEmpty) {
          return const Expanded(child: Center(child: NotesTips()));
        }
        if (_searchTerm.isNotEmpty && filteredData.isEmpty) {
          return const Expanded(
            child: Center(child: Text('No matching books')),
          );
        }
        return Expanded(
          child: AppScrollbar(
            controller: _scrollController,
            child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                controller: _scrollController,
                itemCount: filteredData.length,
                itemBuilder: (context, index) {
                  final item = filteredData[index];
                  return bookNotesItem(
                    book: item['book']!,
                    numberOfNotes: item['numberOfNotes']!,
                    isMobile: isMobile,
                    readingTime: item['readingTime']!,
                    latestTime: item['latestTime'] as String? ?? '',
                  );
                }),
          ),
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }

  Widget bookNotesItem({
    required Book book,
    required int numberOfNotes,
    required bool isMobile,
    required int readingTime,
    required String latestTime,
  }) {
    TextStyle digitStyle = const TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
    );
    TextStyle textStyle = const TextStyle(
      fontSize: 20,
    );
    TextStyle titleStyle = const TextStyle(
      overflow: TextOverflow.ellipsis,
      fontSize: 18,
      fontFamily: 'SourceHanSerif',
      fontWeight: FontWeight.bold,
    );
    TextStyle readingTimeStyle = const TextStyle(
      fontSize: 14,
      color: Colors.grey,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 15, right: 15),
      child: Slidable(
        key: ValueKey(book.id),
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (context) =>
                  _confirmDeleteBookNotes(context, book, numberOfNotes),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              icon: Icons.delete_outline,
              label: L10n.of(context).commonDelete,
              borderRadius: BorderRadius.circular(16),
            ),
          ],
        ),
        child: GestureDetector(
          onSecondaryTapUp: (details) {
            _showContextMenu(
              context,
              details.globalPosition,
              book,
              numberOfNotes,
            );
          },
          onTap: () {
            if (isMobile) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => BookNotesPage(
                          book: book,
                          numberOfNotes: numberOfNotes,
                          isMobile: true,
                        )),
              );
            } else {
              ref
                  .read(notesPageCurrentBookProvider.notifier)
                  .setData(book, numberOfNotes);
            }
          },
          child: FilledContainer(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      highlightDigit(
                        context,
                        L10n.of(context).notesNotes(numberOfNotes),
                        textStyle,
                        digitStyle,
                      ),
                      const SizedBox(height: 8),
                      Text(book.title, style: titleStyle),
                      const SizedBox(height: 18),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Icon(Icons.access_time, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              convertSeconds(readingTime),
                              style: readingTimeStyle,
                            ),
                            Text(" | ", style: readingTimeStyle),
                            Icon(Icons.bar_chart, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${(book.readingPercentage * 100).toStringAsFixed(1)}%',
                              style: readingTimeStyle,
                            ),
                            Text(" | ", style: readingTimeStyle),
                            Text(
                              RelativeTimeFormatter.format(
                                DateTime.tryParse(latestTime),
                              ),
                              style: readingTimeStyle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Expanded(child: SizedBox()),
                Hero(
                  tag: isMobile
                      ? book.coverFullPath
                      : '${book.coverFullPath}notMobile',
                  child: BookCover(
                    book: book,
                    height: 130,
                    width: 90,
                    radius: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteBookNotes(
    BuildContext context,
    Book book,
    int numberOfNotes,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).notesDeleteAllTitle),
        content: Text(
          L10n.of(context).notesDeleteAllDialogContent(
            book.title,
            numberOfNotes,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(L10n.of(context).commonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(bookNotesControllerProvider(book).notifier)
          .deleteAllNotes();
      if (mounted) {
        AnxToast.show(
          L10n.of(context).notesDeleteAllSuccess(book.title),
        );
        final currentBook = ref.read(notesPageCurrentBookProvider).valueOrNull;
        if (currentBook?.book.id == book.id) {
          ref.invalidate(notesPageCurrentBookProvider);
        }
      }
    }
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    Book book,
    int numberOfNotes,
  ) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _confirmDeleteBookNotes(context, book, numberOfNotes);
              }
            });
          },
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                L10n.of(context).notesDeleteAllTitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NotesDetail extends ConsumerWidget {
  const NotesDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookIdAndNotes = ref.watch(bookIdAndNotesProvider);
    if (bookIdAndNotes.valueOrNull?.isEmpty ?? false) {
      return const NotesTips();
    }
    return ref.watch(notesPageCurrentBookProvider).when(
          data: (current) {
            return BookNotesPage(
                isMobile: false,
                book: current.book,
                numberOfNotes: current.numberOfNotes);
          },
          loading: () => const CircularProgressIndicator(),
          error: (error, stack) => NotesTips(),
        );
  }
}
