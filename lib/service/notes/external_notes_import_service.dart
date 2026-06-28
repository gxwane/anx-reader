import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/external_note_import.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/notes/moon_reader_mrexpt_importer.dart';
import 'package:anx_reader/service/notes/pending_notes_import.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/reading_restore_target.dart';
import 'package:anx_reader/utils/webView/anx_headless_webview.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:anx_reader/utils/webView/webview_console_message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ExternalNotesImportService {
  ExternalNotesImportService({
    MoonReaderMrexptImporter? moonReaderImporter,
  }) : _moonReaderImporter = moonReaderImporter ?? MoonReaderMrexptImporter();

  final MoonReaderMrexptImporter _moonReaderImporter;

  Future<ExternalNoteImportReport> importMoonReaderMrexpt({
    required Book book,
    required File file,
    PendingNotesImportSession? session,
  }) async {
    AnxLog.info(
      'ExternalNotesImportService(${book.id}): importing file=${file.path}, '
      'bookTitle="${book.title}", bookPath="${book.fileFullPath}"',
    );
    final parsed = await _moonReaderImporter.parse(file);
    AnxLog.info(
      'ExternalNotesImportService(${book.id}): sourceTitle="${parsed.sourceTitle ?? ''}", '
      'sourcePath="${parsed.sourcePath ?? ''}"',
    );
    if (_looksLikeMismatchedBook(book, parsed.sourceTitle, parsed.sourcePath)) {
      AnxLog.warning(
        'ExternalNotesImportService(${book.id}): source metadata may not match target book. '
        'sourceTitle="${parsed.sourceTitle ?? ''}", sourcePath="${parsed.sourcePath ?? ''}", '
        'targetTitle="${book.title}", targetPath="${book.fileFullPath}"',
      );
    }
    if (parsed.records.isEmpty) {
      AnxLog.warning(
        'ExternalNotesImportService(${book.id}): no records parsed, parseErrors=${parsed.parseErrors}',
      );
      return ExternalNoteImportReport(
        parsed: 0,
        resolved: 0,
        imported: 0,
        duplicates: 0,
        unresolved: 0,
        parseErrors: parsed.parseErrors,
      );
    }

    session?.throwIfCancelled();
    final resolved = await _resolveRecords(book, parsed.records);
    session?.throwIfCancelled();
    AnxLog.info(
      'ExternalNotesImportService(${book.id}): parsed=${parsed.records.length}, resolved=${resolved.length}',
    );
    final existing = await bookNoteDao.selectBookNotesByBookId(book.id);
    final signatures = existing.map(_signature).toSet();
    var imported = 0;
    var duplicates = 0;

    session?.markWritingStarted();
    for (final resolvedNote in resolved) {
      final note = resolvedNote.toBookNote(book.id);
      final signature = _signature(note);
      if (signatures.contains(signature)) {
        duplicates++;
        continue;
      }
      await bookNoteDao.insert(BookNoteDao.table, note.toMap());
      signatures.add(signature);
      imported++;
    }

    AnxLog.info(
      'ExternalNotesImportService(${book.id}): imported=$imported, duplicates=$duplicates, unresolved=${parsed.records.length - resolved.length}, parseErrors=${parsed.parseErrors}',
    );

    return ExternalNoteImportReport(
      parsed: parsed.records.length,
      resolved: resolved.length,
      imported: imported,
      duplicates: duplicates,
      unresolved: parsed.records.length - resolved.length,
      parseErrors: parsed.parseErrors,
    );
  }

  Future<List<ResolvedExternalNote>> _resolveRecords(
    Book book,
    List<ExternalNoteRecord> records,
  ) async {
    final payload = [
      for (var i = 0; i < records.length; i++) records[i].toResolveJson(i),
    ];

    final player = epubPlayerKey.currentState;
    if (player != null && player.book.id == book.id) {
      AnxLog.info(
        'ExternalNotesImportService(${book.id}): resolving with active reader, payload=${payload.length}',
      );
      return _parseResolved(await player.resolveExternalNotes(payload));
    }

    AnxLog.info(
      'ExternalNotesImportService(${book.id}): resolving with headless reader, payload=${payload.length}',
    );
    if (Platform.isWindows) {
      throw StateError(
        'Windows notes import requires the target book to be open. '
        'Background WebView2 reader instances are disabled to avoid native crashes.',
      );
    }
    return _resolveWithHeadlessReader(book, payload);
  }

  Future<List<ResolvedExternalNote>> _resolveWithHeadlessReader(
    Book book,
    List<Map<String, dynamic>> payload,
  ) async {
    if (Platform.isWindows && webViewEnvironment == null) {
      throw StateError(
        'WebViewEnvironment is not initialized. WebView2 Runtime may not be installed.',
      );
    }

    final loadCompleter = Completer<void>();
    final readyCompleter = Completer<void>();
    InAppWebViewController? controller;

    final encodedPath = Uri.encodeComponent(book.fileFullPath);
    final bookUrl = 'http://127.0.0.1:${Server().port}/book/$encodedPath';
    final initialLocation = decodeReadingRestoreTarget(
      book.lastReadPosition,
      fallbackFraction: book.readingPercentage,
    );
    final url = generateUrl(bookUrl, initialLocation, importing: false);

    final headless = AnxHeadlessWebView(
      webViewEnvironment: webViewEnvironment,
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        supportZoom: false,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (createdController) {
        controller = createdController;
        createdController.addJavaScriptHandler(
          handlerName: 'onLoadEnd',
          callback: (_) {
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete();
            }
            return null;
          },
        );
      },
      onLoadStop: (_, __) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.complete();
        }
      },
      onConsoleMessage: webviewConsoleMessage,
      onLoadError: (_, __, code, message) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.completeError(
            Exception('Failed to load reader: [$code] $message'),
          );
        }
      },
      onLoadHttpError: (_, __, statusCode, description) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.completeError(
            Exception(
                'HTTP error while loading reader: [$statusCode] $description'),
          );
        }
      },
    );

    try {
      await headless.run();
      await loadCompleter.future.timeout(const Duration(seconds: 15));
      await readyCompleter.future.timeout(const Duration(seconds: 15));
      final activeController = controller;
      if (activeController == null) {
        throw StateError('WebView controller is not initialized');
      }
      final encoded = jsonEncode(payload);
      final result = await activeController.callAsyncJavaScript(
        functionBody: 'return await resolveExternalNotes($encoded)',
      );
      final parsed = _parseResolved(result?.value);
      AnxLog.info(
        'ExternalNotesImportService(${book.id}): headless resolved=${parsed.length}',
      );
      return parsed;
    } catch (error, stackTrace) {
      AnxLog.warning(
        'ExternalNotesImportService(${book.id}): failed to resolve notes: $error',
        stackTrace,
      );
      rethrow;
    } finally {
      await headless.dispose();
    }
  }

  List<ResolvedExternalNote> _parseResolved(dynamic result) {
    if (result is! List) {
      AnxLog.warning(
        'ExternalNotesImportService: invalid resolve result type=${result.runtimeType}',
      );
      return const [];
    }
    final parsed = result
        .whereType<Map<dynamic, dynamic>>()
        .map(ResolvedExternalNote.fromJson)
        .where((note) => note.target.isNotEmpty && note.content.isNotEmpty)
        .toList();
    AnxLog.info(
      'ExternalNotesImportService: resolve result raw=${result.length}, parsed=${parsed.length}',
    );
    return parsed;
  }

  String _signature(BookNote note) {
    return jsonEncode({
      'target': note.cfi,
      'content': note.content.trim(),
      'readerNote': note.readerNote?.trim() ?? '',
      'type': note.type,
      'color': note.color.toUpperCase(),
    });
  }

  bool _looksLikeMismatchedBook(
    Book book,
    String? sourceTitle,
    String? sourcePath,
  ) {
    final targetTitle = _normalizeBookIdentity(book.title);
    final targetFile = _normalizeBookIdentity(_basename(book.fileFullPath));
    final sourceTitleNormalized = _normalizeBookIdentity(sourceTitle ?? '');
    final sourceFile = _normalizeBookIdentity(_basename(sourcePath ?? ''));
    final sourceCandidates = [
      sourceTitleNormalized,
      sourceFile,
    ].where((value) => value.length >= 4).toList();
    if (sourceCandidates.isEmpty) return false;

    final targetCandidates = [
      targetTitle,
      targetFile,
    ].where((value) => value.length >= 4).toList();
    if (targetCandidates.isEmpty) return false;

    for (final source in sourceCandidates) {
      for (final target in targetCandidates) {
        if (source.contains(target) || target.contains(source)) {
          return false;
        }
      }
    }
    return true;
  }

  String _basename(String path) {
    if (path.isEmpty) return '';
    return path.split(RegExp(r'[\\/]')).last;
  }

  String _normalizeBookIdentity(String value) {
    final withoutExtension = value.replaceFirst(
      RegExp(r'\.(epub|mobi|azw3|fb2|txt|pdf)$', caseSensitive: false),
      '',
    );
    return withoutExtension
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\\/_\-.()[\],:;]+'), '');
  }
}
