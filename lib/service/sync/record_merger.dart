import 'dart:math';

/// Pure functional core for non-destructive record-level merging.
///
/// Handles cross-device SQLite auto-increment ID translation using immutable
/// [file_md5] keys, tombstone-based note soft deletions, and reading time merges.
class RecordMerger {
  RecordMerger._();

  /// Merges local and remote book rows by [file_md5].
  ///
  /// Chooses the record with the newer [update_time]. If the remote book does
  /// not exist locally, it is preserved for insertion.
  static List<Map<String, dynamic>> mergeBooks({
    required List<Map<String, dynamic>> localBooks,
    required List<Map<String, dynamic>> remoteBooks,
  }) {
    final mergedMap = <String, Map<String, dynamic>>{};

    for (final book in localBooks) {
      final md5 = book['file_md5'] as String?;
      if (md5 != null && md5.isNotEmpty) {
        mergedMap[md5] = Map<String, dynamic>.from(book);
      }
    }

    for (final remote in remoteBooks) {
      final md5 = remote['file_md5'] as String?;
      if (md5 == null || md5.isEmpty) continue;

      if (!mergedMap.containsKey(md5)) {
        mergedMap[md5] = Map<String, dynamic>.from(remote);
      } else {
        final local = mergedMap[md5]!;
        final localTime = _parseDateTime(local['update_time']);
        final remoteTime = _parseDateTime(remote['update_time']);

        if (remoteTime.isAfter(localTime)) {
          // Remote is newer, merge properties while preserving local ID if present
          final localId = local['id'];
          final updated = Map<String, dynamic>.from(remote);
          if (localId != null) updated['id'] = localId;
          mergedMap[md5] = updated;
        }
      }
    }

    return mergedMap.values.toList(growable: false);
  }

  /// Merges local and remote notes using [cfi] + [file_md5] and translates
  /// remote foreign keys to the local [book_id].
  ///
  /// Supports tombstone soft-deletion: if a note was deleted (`is_deleted == 1`)
  /// with a newer [update_time], the deleted state wins.
  static List<Map<String, dynamic>> mergeNotes({
    required List<Map<String, dynamic>> localNotes,
    required List<Map<String, dynamic>> remoteNotes,
    required Map<String, int> md5ToLocalBookId,
  }) {
    // Key: "$fileMd5|$cfi"
    final mergedNotes = <String, Map<String, dynamic>>{};

    for (final note in localNotes) {
      final md5 = note['file_md5'] as String? ?? '';
      final cfi = note['cfi'] as String? ?? '';
      if (cfi.isEmpty) continue;
      final compositeKey = '$md5|$cfi';
      mergedNotes[compositeKey] = Map<String, dynamic>.from(note);
    }

    for (final remote in remoteNotes) {
      final md5 = remote['file_md5'] as String? ?? '';
      final cfi = remote['cfi'] as String? ?? '';
      if (cfi.isEmpty) continue;
      final compositeKey = '$md5|$cfi';

      final targetLocalBookId = md5ToLocalBookId[md5] ?? 0;

      if (!mergedNotes.containsKey(compositeKey)) {
        final newNote = Map<String, dynamic>.from(remote);
        newNote.remove('id'); // MUST strip remote primary key for new local record
        newNote['book_id'] = targetLocalBookId; // Always set mapped local ID (0 if unmapped)
        mergedNotes[compositeKey] = newNote;
      } else {
        final local = mergedNotes[compositeKey]!;
        final localTime = _parseDateTime(local['update_time']);
        final remoteTime = _parseDateTime(remote['update_time']);

        if (remoteTime.isAfter(localTime)) {
          final localId = local['id'];
          final updated = Map<String, dynamic>.from(remote);
          if (localId != null) {
            updated['id'] = localId; // Preserve existing local primary key
          } else {
            updated.remove('id');
          }
          updated['book_id'] = targetLocalBookId;
          mergedNotes[compositeKey] = updated;
        }
      }
    }

    return mergedNotes.values.toList(growable: false);
  }

  /// Merges daily reading time records by [file_md5] and [date], resolving
  /// to the maximum reading time recorded on either device to prevent lost stats.
  static List<Map<String, dynamic>> mergeReadingTimes({
    required List<Map<String, dynamic>> localReadingTimes,
    required List<Map<String, dynamic>> remoteReadingTimes,
    required Map<String, int> md5ToLocalBookId,
  }) {
    // Key: "$fileMd5|$date"
    final mergedMap = <String, Map<String, dynamic>>{};

    for (final record in localReadingTimes) {
      final md5 = record['file_md5'] as String? ?? '';
      final date = record['date'] as String? ?? '';
      if (date.isEmpty) continue;
      final key = '$md5|$date';
      mergedMap[key] = Map<String, dynamic>.from(record);
    }

    for (final remote in remoteReadingTimes) {
      final md5 = remote['file_md5'] as String? ?? '';
      final date = remote['date'] as String? ?? '';
      if (date.isEmpty) continue;
      final key = '$md5|$date';

      final targetBookId = md5ToLocalBookId[md5] ?? 0;

      if (!mergedMap.containsKey(key)) {
        final newRec = Map<String, dynamic>.from(remote);
        newRec.remove('id'); // MUST strip remote primary key for new local record
        newRec['book_id'] = targetBookId;
        mergedMap[key] = newRec;
      } else {
        final local = mergedMap[key]!;
        final localSeconds = local['reading_time'] as int? ?? 0;
        final remoteSeconds = remote['reading_time'] as int? ?? 0;
        local['reading_time'] = max(localSeconds, remoteSeconds);
        local['book_id'] = targetBookId;
      }
    }

    return mergedMap.values.toList(growable: false);
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (value is DateTime) return value.toUtc();
    try {
      return DateTime.parse(value.toString()).toUtc();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }
}
