import 'dart:io' as io;
import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/service/sync/record_merger.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Service responsible for performing non-destructive 3-way in-memory merging
/// between a remote WebDAV database snapshot and the local active SQLite database.
class DatabaseMerger {
  DatabaseMerger._();

  /// Downloads the remote database snapshot, parses records, and merges them
  /// transactionally into the active local database.
  static Future<bool> mergeFromRemote({
    required SyncClientBase client,
    required String remoteDbFileName,
  }) async {
    final tempDir = await getAnxTempDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDbPath = join(tempDir.path, 'remote_merge_$timestamp.db');

    Database? remoteDb;
    try {
      AnxLog.info('DatabaseMerger: Downloading remote DB for in-memory merge');
      await client.downloadFile(
        AppIdentity.syncPath(remoteDbFileName),
        tempDbPath,
      );

      final tempFile = io.File(tempDbPath);
      if (!tempFile.existsSync() || tempFile.lengthSync() < 1024) {
        AnxLog.warning('DatabaseMerger: Remote DB file invalid or too small');
        return false;
      }

      await DBHelper.fixDatabaseHeader(tempDbPath);

      // Open remote DB in read-only mode
      if (AnxPlatform.isWindows || AnxPlatform.isLinux || AnxPlatform.isMacOS) {
        sqfliteFfiInit();
        remoteDb = await databaseFactoryFfi.openDatabase(
          tempDbPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
      } else {
        remoteDb = await openDatabase(
          tempDbPath,
          readOnly: true,
          singleInstance: false,
        );
      }

      // 1. Extract remote tables
      final remoteBooks = await remoteDb.rawQuery('SELECT * FROM tb_books');
      final remoteNotes = await remoteDb.rawQuery('SELECT * FROM tb_notes');
      final remoteReadingTimes =
          await remoteDb.rawQuery('SELECT * FROM tb_reading_time');

      // 2. Extract local tables
      final localDb = await DBHelper().database;
      final localBooks = await localDb.rawQuery('SELECT * FROM tb_books');
      final localNotes = await localDb.rawQuery('SELECT * FROM tb_notes');
      final localReadingTimes =
          await localDb.rawQuery('SELECT * FROM tb_reading_time');

      // 3. Build immutable file_md5 to local book_id mapping
      final md5ToLocalBookId = <String, int>{};
      for (final b in localBooks) {
        final md5 = b['file_md5'] as String?;
        final id = b['id'] as int?;
        if (md5 != null && md5.isNotEmpty && id != null) {
          md5ToLocalBookId[md5] = id;
        }
      }

      // 4. Perform pure functional merges
      final mergedBooks = RecordMerger.mergeBooks(
        localBooks: localBooks,
        remoteBooks: remoteBooks,
      );

      // 5. Execute transactional write-back into local DB
      await localDb.transaction((txn) async {
        // A. Apply merged books
        for (final book in mergedBooks) {
          final md5 = book['file_md5'] as String? ?? '';
          if (md5.isEmpty) continue;

          final existingId = md5ToLocalBookId[md5];
          final bookMap = Map<String, dynamic>.from(book);
          bookMap.remove('id'); // do not overwrite primary key

          if (existingId != null) {
            await txn.update(
              'tb_books',
              bookMap,
              where: 'id = ?',
              whereArgs: [existingId],
            );
          } else {
            final newId = await txn.insert('tb_books', bookMap);
            md5ToLocalBookId[md5] = newId;
          }
        }

        // B. Attach file_md5 to notes and reading times for cross-device resolution
        final localNotesWithMd5 = _attachMd5ToRecords(localNotes, localBooks);
        final remoteNotesWithMd5 = _attachMd5ToRecords(remoteNotes, remoteBooks);

        final mergedNotes = RecordMerger.mergeNotes(
          localNotes: localNotesWithMd5,
          remoteNotes: remoteNotesWithMd5,
          md5ToLocalBookId: md5ToLocalBookId,
        );

        for (final note in mergedNotes) {
          final noteMap = Map<String, dynamic>.from(note);
          noteMap.remove('file_md5');
          final id = noteMap['id'];

          if (id != null && (noteMap['book_id'] as int? ?? 0) != 0) {
            await txn.update(
              'tb_notes',
              noteMap,
              where: 'id = ?',
              whereArgs: [id],
            );
          } else if ((noteMap['book_id'] as int? ?? 0) != 0) {
            noteMap.remove('id');
            await txn.insert('tb_notes', noteMap);
          }
        }

        // C. Apply merged reading times
        final localTimesWithMd5 =
            _attachMd5ToRecords(localReadingTimes, localBooks);
        final remoteTimesWithMd5 =
            _attachMd5ToRecords(remoteReadingTimes, remoteBooks);

        final mergedTimes = RecordMerger.mergeReadingTimes(
          localReadingTimes: localTimesWithMd5,
          remoteReadingTimes: remoteTimesWithMd5,
          md5ToLocalBookId: md5ToLocalBookId,
        );

        for (final rt in mergedTimes) {
          final rtMap = Map<String, dynamic>.from(rt);
          rtMap.remove('file_md5');
          final bookId = rtMap['book_id'] as int? ?? 0;
          final date = rtMap['date'] as String? ?? '';
          if (bookId == 0 || date.isEmpty) continue;

          final existing = await txn.rawQuery(
            'SELECT id FROM tb_reading_time WHERE book_id = ? AND date = ?',
            [bookId, date],
          );

          if (existing.isNotEmpty) {
            await txn.update(
              'tb_reading_time',
              {'reading_time': rtMap['reading_time']},
              where: 'id = ?',
              whereArgs: [existing.first['id']],
            );
          } else {
            rtMap.remove('id');
            await txn.insert('tb_reading_time', rtMap);
          }
        }
      });

      AnxLog.info('DatabaseMerger: Successfully merged remote records into local database');
      return true;
    } catch (e) {
      AnxLog.severe('DatabaseMerger: Failed to merge remote database: $e');
      return false;
    } finally {
      await remoteDb?.close();
      final tempFile = io.File(tempDbPath);
      if (tempFile.existsSync()) await tempFile.delete();
    }
  }

  static List<Map<String, dynamic>> _attachMd5ToRecords(
    List<Map<String, dynamic>> records,
    List<Map<String, dynamic>> books,
  ) {
    final idToMd5 = <int, String>{};
    for (final b in books) {
      final id = b['id'] as int?;
      final md5 = b['file_md5'] as String?;
      if (id != null && md5 != null && md5.isNotEmpty) {
        idToMd5[id] = md5;
      }
    }

    return records.map((r) {
      final map = Map<String, dynamic>.from(r);
      final bookId = map['book_id'] as int?;
      if (bookId != null && idToMd5.containsKey(bookId)) {
        map['file_md5'] = idToMd5[bookId];
      }
      return map;
    }).toList(growable: false);
  }
}
