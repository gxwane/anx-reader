import 'dart:async';
import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class ExternalFileReceiver {
  static const MethodChannel _channel =
      MethodChannel('anx_reader/desktop_file_open');

  static String? pendingStartupFilePath;
  static bool _isInitialized = false;
  static DateTime? _lastHandledTime;
  static String? _lastHandledPath;

  /// Clear debounce tracking so the same file can be re-opened immediately
  static void clearLastHandled() {
    _lastHandledPath = null;
    _lastHandledTime = null;
  }

  /// Check whether an extension is supported by Anx Reader
  static bool isSupportedBookFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    return allowBookExtensions.contains(ext);
  }

  /// Clean file path argument by removing surrounding quotes and validating file
  static String? cleanFilePathFromArgs(List<String> args) {
    for (final raw in args) {
      var arg = raw.trim();
      // Skip empty args or command-line flags
      if (arg.isEmpty || arg.startsWith('-')) {
        continue;
      }
      // Strip surrounding quotes
      if ((arg.startsWith('"') && arg.endsWith('"')) ||
          (arg.startsWith("'") && arg.endsWith("'"))) {
        arg = arg.substring(1, arg.length - 1).trim();
      }

      if (arg.isNotEmpty && isSupportedBookFile(arg)) {
        final file = File(arg);
        if (file.existsSync()) {
          return file.path;
        }
      }
    }
    return null;
  }

  /// Store cold start argument from main(args)
  static void setInitialFilePathFromArgs(List<String> args) {
    final cleaned = cleanFilePathFromArgs(args);
    if (cleaned != null) {
      pendingStartupFilePath = cleaned;
      AnxLog.info('ExternalFileReceiver: pending startup file set to: $cleaned');
    }
  }

  /// Stream-based MD5 computation to avoid OOM on large files
  static Future<String?> calculateFileMd5Stream(File file) async {
    try {
      final digest = await md5.bind(file.openRead()).first;
      return digest.toString();
    } catch (e) {
      AnxLog.warning('ExternalFileReceiver: failed to calculate MD5 stream: $e');
      return null;
    }
  }

  /// Initialize receiver: registers desktop MethodChannel listener and consumes pending cold start file
  static Future<void> init(WidgetRef ref) async {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenFile') {
        final rawPath = call.arguments as String?;
        if (rawPath != null && rawPath.isNotEmpty) {
          final cleaned = cleanFilePathFromArgs([rawPath]);
          if (cleaned != null) {
            await handleIncomingFile(File(cleaned), ref);
          }
        }
      }
    });

    try {
      await _channel.invokeMethod('ready');
    } catch (e) {
      AnxLog.warning('ExternalFileReceiver: native ready handshake error: $e');
    }

    // Consume pending startup file once context and home page are ready
    if (pendingStartupFilePath != null) {
      final path = pendingStartupFilePath!;
      pendingStartupFilePath = null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await handleIncomingFile(File(path), ref);
      });
    }
  }

  /// Unified entry point for opening an incoming external book file
  static Future<void> handleIncomingFile(File file, WidgetRef ref) async {
    if (!file.existsSync()) {
      return;
    }

    final now = DateTime.now();
    if (_lastHandledPath == file.path &&
        _lastHandledTime != null &&
        now.difference(_lastHandledTime!).inMilliseconds < 1500) {
      AnxLog.info(
          'ExternalFileReceiver: debouncing duplicate incoming file: ${file.path}');
      return;
    }
    _lastHandledTime = now;
    _lastHandledPath = file.path;

    try {
      final md5Str = await calculateFileMd5Stream(file);
      Book? existingBook;
      if (md5Str != null) {
        existingBook = await bookDao.getBookByMd5(md5Str);
      }

      // Check if user is currently reading this exact book in foreground
      final currentReading = ref.read(currentReadingProvider);
      final isActivelyReading =
          currentReading.isReading && readingPageKey.currentState != null;
      if (isActivelyReading &&
          md5Str != null &&
          currentReading.book?.md5 == md5Str) {
        AnxLog.info(
            'ExternalFileReceiver: book is already open in foreground: ${file.path}');
        return;
      }

      // Route guard: if reading another book or reader is active, pop to first route
      if (isActivelyReading || readingPageKey.currentState != null) {
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
        await Future.delayed(const Duration(milliseconds: 150));
      }

      // Branch 1: Book already exists on bookshelf -> Fast Path (<50ms)
      if (existingBook != null &&
          !existingBook.isDeleted &&
          File(existingBook.fileFullPath).existsSync()) {
        if (navigatorKey.currentContext != null) {
          await pushToReadingPage(ref, navigatorKey.currentContext!, existingBook);
        }
        return;
      }

      // Branch 2: Book is NOT in library -> Option B: Ephemeral Preview Mode
      File displayFile = file;
      if (p.extension(file.path).toLowerCase() == '.txt') {
        displayFile = await convertFromTxt(file);
      }

      final tempBook = Book(
        id: -1,
        title: p.basenameWithoutExtension(file.path),
        coverPath: '',
        filePath: displayFile.path, // Absolute path
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Unknown',
        isDeleted: false,
        rating: 0.0,
        md5: md5Str,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      if (navigatorKey.currentContext != null) {
        await pushToReadingPage(ref, navigatorKey.currentContext!, tempBook);
      }
    } catch (e, stack) {
      AnxLog.severe(
          'ExternalFileReceiver: failed to handle incoming file ${file.path}: $e',
          e,
          stack);
    }
  }

  /// Safely import an ephemeral preview book into the library without mutating original file
  static Future<Book?> importExternalBookToLibrary({
    required BuildContext context,
    required WidgetRef ref,
    required Book tempBook,
  }) async {
    try {
      final originalFile = File(tempBook.filePath);
      if (!originalFile.existsSync()) {
        return null;
      }

      // Safe clone to temp dir so original external file is NEVER deleted
      final tempDir = await getAnxTempDir();
      final safeClone = await originalFile.copy(p.join(
        tempDir.path,
        'import_${DateTime.now().millisecondsSinceEpoch}_${p.basename(originalFile.path)}',
      ));

      await getBookMetadata(safeClone, md5: tempBook.md5, ref: ref);

      final imported = tempBook.md5 != null
          ? await bookDao.getBookByMd5(tempBook.md5!)
          : null;

      if (imported != null) {
        // Migrate any temporary notes created during preview session
        await bookNoteDao.migrateTemporaryNotes(imported.id);

        ref.read(bookListProvider.notifier).refresh();
        return imported;
      }
    } catch (e, stack) {
      AnxLog.severe(
          'ExternalFileReceiver: failed to import external book: $e', e, stack);
    }
    return null;
  }
}
