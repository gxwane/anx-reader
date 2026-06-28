import 'dart:io';

import 'package:anx_reader/models/book.dart';

class NotesImportCancelledException implements Exception {
  const NotesImportCancelledException();

  @override
  String toString() => 'Notes import was cancelled';
}

class PendingNotesImportSession {
  PendingNotesImportSession({
    required this.book,
    required this.file,
  });

  final Book book;
  final File file;

  bool _started = false;
  bool _cancelled = false;
  bool _writingStarted = false;

  bool get started => _started;
  bool get cancelled => _cancelled;
  bool get writingStarted => _writingStarted;

  void markStarted() {
    _started = true;
  }

  void markWritingStarted() {
    _writingStarted = true;
  }

  void cancelIfResolving() {
    if (!_writingStarted) {
      _cancelled = true;
    }
  }

  void throwIfCancelled() {
    if (_cancelled && !_writingStarted) {
      throw const NotesImportCancelledException();
    }
  }
}

class PendingNotesImportController {
  PendingNotesImportSession? _pending;

  PendingNotesImportSession start({
    required Book book,
    required File file,
  }) {
    _pending?.cancelIfResolving();
    final session = PendingNotesImportSession(book: book, file: file);
    _pending = session;
    return session;
  }

  PendingNotesImportSession? takeForBook(Book book) {
    final session = _pending;
    if (session == null || session.book.id != book.id || session.started) {
      return null;
    }
    session.markStarted();
    _pending = null;
    return session;
  }

  void cancel(PendingNotesImportSession session) {
    session.cancelIfResolving();
    if (identical(_pending, session)) {
      _pending = null;
    }
  }
}

final pendingNotesImportController = PendingNotesImportController();
