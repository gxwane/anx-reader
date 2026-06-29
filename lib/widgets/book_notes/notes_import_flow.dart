import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/providers/notes_page_current_book.dart';
import 'package:anx_reader/providers/notes_statistics.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/notes/external_notes_import_service.dart';
import 'package:anx_reader/service/notes/pending_notes_import.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> importMoonReaderNotesForBook({
  required BuildContext context,
  required WidgetRef ref,
  required Book book,
  File? file,
}) async {
  final selectedFile = file ?? await _pickMoonReaderMrexptFile(context);
  if (selectedFile == null) return;
  if (!context.mounted) return;

  if (Platform.isWindows && !_isBookActiveInReader(book)) {
    final session = pendingNotesImportController.start(
      book: book,
      file: selectedFile,
    );
    AnxLog.info(
      'Notes import: opening reader for Windows active resolve, bookId=${book.id}, file=${selectedFile.path}',
    );
    await pushToReadingPage(ref, context, book);
    if (!session.started) {
      pendingNotesImportController.cancel(session);
      AnxLog.warning(
        'Notes import: reader was not opened for pending import, bookId=${book.id}',
      );
    }
    return;
  }

  try {
    AnxLog.info(
        'Notes import: start bookId=${book.id}, file=${selectedFile.path}');
    final report = await ExternalNotesImportService().importMoonReaderMrexpt(
      book: book,
      file: selectedFile,
    );

    refreshNotesImportProviders(ref, book);

    if (context.mounted) {
      AnxToast.show(
        L10n.of(context).notesImportSummary(
          report.imported,
          report.duplicates,
          report.unresolved,
          report.parseErrors,
        ),
      );
    }
  } catch (error, stackTrace) {
    AnxLog.warning(
        'Notes import: failed bookId=${book.id}: $error', stackTrace);
    if (context.mounted) {
      AnxToast.show(L10n.of(context).importFailed(error));
    }
  }
}

Future<void> importMoonReaderNotesWithBookPicker({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final file = await _pickMoonReaderMrexptFile(context);
  if (file == null) return;
  if (!context.mounted) return;

  final book = AnxPlatform.isDesktop
      ? await showDialog<Book>(
          context: context,
          builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(40),
            child: const _NotesImportBookPicker(),
          ),
        )
      : await showModalBottomSheet<Book>(
          context: context,
          isScrollControlled: true,
          builder: (context) => const _NotesImportBookPicker(),
        );
  if (book == null || !context.mounted) {
    AnxLog.info('Notes import: user cancelled book picker');
    return;
  }

  await importMoonReaderNotesForBook(
    context: context,
    ref: ref,
    book: book,
    file: file,
  );
}

Future<File?> _pickMoonReaderMrexptFile(BuildContext context) async {
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
  } catch (error, stackTrace) {
    AnxLog.warning('Notes import: file picker failed: $error', stackTrace);
    if (context.mounted) {
      AnxToast.show(L10n.of(context).importFailed(error));
    }
    return null;
  }

  final path = result?.files.single.path;
  if (path == null || path.isEmpty) {
    AnxLog.info('Notes import: user cancelled file picker');
    return null;
  }
  if (!path.toLowerCase().endsWith('.mrexpt')) {
    AnxLog.warning('Notes import: unsupported file selected: $path');
    if (context.mounted) {
      AnxToast.show(L10n.of(context).notesImportUnsupportedFile);
    }
    return null;
  }
  return File(path);
}

bool _isBookActiveInReader(Book book) =>
    epubPlayerKey.currentState?.book.id == book.id;

void refreshNotesImportProviders(WidgetRef ref, Book book) {
  ref.invalidate(bookNotesControllerProvider(book));
  ref.invalidate(bookIdAndNotesProvider);
  ref.invalidate(notesStatisticsProvider);
  ref.invalidate(notesPageCurrentBookProvider);
}

class _NotesImportBookPicker extends StatefulWidget {
  const _NotesImportBookPicker();

  @override
  State<_NotesImportBookPicker> createState() => _NotesImportBookPickerState();
}

class _NotesImportBookPickerState extends State<_NotesImportBookPicker> {
  final TextEditingController _controller = TextEditingController();
  late Future<List<Book>> _booksFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _booksFuture = bookDao.selectNotDeleteBooks();
    _controller.addListener(() {
      setState(() {
        _query = _controller.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
          maxWidth: AnxPlatform.isDesktop ? 500 : double.infinity,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.notesPageImport,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: l10n.startTypingToSearch,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Book>>(
                future: _booksFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final books = (snapshot.data ?? const <Book>[])
                      .where((book) =>
                          _query.isEmpty ||
                          book.title.toLowerCase().contains(_query) ||
                          book.author.toLowerCase().contains(_query))
                      .toList();
                  if (books.isEmpty) {
                    return Center(child: Text(l10n.bookshelfTips_1));
                  }
                  return ListView.builder(
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        leading: BookCover(book: book, width: 36),
                        title: Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, book),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
