import 'dart:convert';
import 'dart:io' as io;

import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync/book_notes_payload.dart';
import 'package:anx_reader/models/sync/book_progress_payload.dart';
import 'package:anx_reader/service/sync/record_merger.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';

/// Manager for lightweight single-book progress and notes micro-synchronization
/// over WebDAV, as well as aggregated bookshelf progress indexing.
class ProgressSyncManager {
  final SyncClientBase _client;

  ProgressSyncManager(this._client);

  static const String progressDir = 'sync/progress';
  static const String notesDir = 'sync/notes';
  static const String latestProgressFile = 'sync/latest_progress.json';

  /// Uploads single-book progress payload to [sync/progress/<file_md5>.json]
  /// and updates the aggregated index.
  Future<void> uploadBookProgress(Book book) async {
    final md5 = book.md5;
    if (md5 == null || md5.isEmpty) {
      AnxLog.warning('ProgressSyncManager: Book has no MD5, skipping progress upload');
      return;
    }

    try {
      final payload = BookProgressPayload(
        fileMd5: md5,
        lastReadPosition: book.lastReadPosition,
        readingPercentage: book.readingPercentage,
        readingStatus: book.status.name,
        updatedAt: book.updateTime,
        deviceName: AnxPlatform.type.name,
      );

      final tempDir = await getAnxTempDir();
      final localFile = io.File('${tempDir.path}/progress_$md5.json');
      await localFile.writeAsString(jsonEncode(payload.toJson()));

      final remotePath = AppIdentity.syncPath('$progressDir/$md5.json');
      await _client.uploadFile(localFile.path, remotePath, replace: true);
      if (localFile.existsSync()) await localFile.delete();

      AnxLog.info('ProgressSyncManager: Uploaded progress for book: ${book.title}');
    } catch (e) {
      AnxLog.warning('ProgressSyncManager: Failed to upload book progress: $e');
    }
  }

  /// Fetches single-book progress from [sync/progress/<file_md5>.json].
  Future<BookProgressPayload?> fetchRemoteProgress(String fileMd5) async {
    if (fileMd5.isEmpty) return null;

    try {
      final tempDir = await getAnxTempDir();
      final localFile = io.File('${tempDir.path}/remote_progress_$fileMd5.json');
      final remotePath = AppIdentity.syncPath('$progressDir/$fileMd5.json');

      await _client.downloadFile(remotePath, localFile.path);
      if (!localFile.existsSync()) return null;

      final content = await localFile.readAsString();
      await localFile.delete();

      final json = jsonDecode(content) as Map<String, dynamic>;
      return BookProgressPayload.fromJson(json);
    } catch (e) {
      AnxLog.info('ProgressSyncManager: No remote progress found for $fileMd5: $e');
      return null;
    }
  }

  /// Uploads all notes for a book (including tombstones) to [sync/notes/<file_md5>.json].
  Future<void> uploadBookNotes(Book book) async {
    final md5 = book.md5;
    if (md5 == null || md5.isEmpty) return;

    try {
      final db = await DBHelper().database;
      final rawNotes = await db.rawQuery(
        'SELECT * FROM tb_notes WHERE book_id = ?',
        [book.id],
      );

      final notesWithMd5 = rawNotes.map((n) {
        final map = Map<String, dynamic>.from(n);
        map['file_md5'] = md5;
        return map;
      }).toList(growable: false);

      final payload = BookNotesPayload(
        fileMd5: md5,
        notes: notesWithMd5,
        updatedAt: DateTime.now(),
      );

      final tempDir = await getAnxTempDir();
      final localFile = io.File('${tempDir.path}/notes_$md5.json');
      await localFile.writeAsString(jsonEncode(payload.toJson()));

      final remotePath = AppIdentity.syncPath('$notesDir/$md5.json');
      await _client.uploadFile(localFile.path, remotePath, replace: true);
      if (localFile.existsSync()) await localFile.delete();

      AnxLog.info('ProgressSyncManager: Uploaded ${notesWithMd5.length} notes for ${book.title}');
    } catch (e) {
      AnxLog.warning('ProgressSyncManager: Failed to upload notes: $e');
    }
  }

  /// Merges remote notes from [sync/notes/<file_md5>.json] into the local database.
  Future<void> mergeRemoteNotes(Book book) async {
    final md5 = book.md5;
    if (md5 == null || md5.isEmpty) return;

    try {
      final tempDir = await getAnxTempDir();
      final localFile = io.File('${tempDir.path}/remote_notes_$md5.json');
      final remotePath = AppIdentity.syncPath('$notesDir/$md5.json');

      await _client.downloadFile(remotePath, localFile.path);
      if (!localFile.existsSync()) return;

      final content = await localFile.readAsString();
      await localFile.delete();

      final json = jsonDecode(content) as Map<String, dynamic>;
      final payload = BookNotesPayload.fromJson(json);

      final db = await DBHelper().database;
      final rawLocalNotes = await db.rawQuery(
        'SELECT * FROM tb_notes WHERE book_id = ?',
        [book.id],
      );

      final localNotesWithMd5 = rawLocalNotes.map((n) {
        final map = Map<String, dynamic>.from(n);
        map['file_md5'] = md5;
        return map;
      }).toList(growable: false);

      final merged = RecordMerger.mergeNotes(
        localNotes: localNotesWithMd5,
        remoteNotes: payload.notes,
        md5ToLocalBookId: {md5: book.id},
      );

      await db.transaction((txn) async {
        for (final note in merged) {
          final id = note['id'];
          final mapToSave = Map<String, dynamic>.from(note);
          mapToSave.remove('id');
          mapToSave.remove('file_md5');
          mapToSave['book_id'] = book.id;

          if (id != null) {
            await txn.update(
              'tb_notes',
              mapToSave,
              where: 'id = ?',
              whereArgs: [id],
            );
          } else {
            await txn.insert('tb_notes', mapToSave);
          }
        }
      });

      AnxLog.info('ProgressSyncManager: Successfully merged remote notes for ${book.title}');
    } catch (e) {
      AnxLog.info('ProgressSyncManager: No remote notes to merge or error: $e');
    }
  }
}
