import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:sqflite/sqflite.dart';

/// Restores validated business data from a local backup into the open database.
/// Backup schema, triggers, views, sync state and device-specific paths are not
/// installed into the live database.
class DatabaseRestore {
  static const tables = [
    'tb_groups',
    'tb_books',
    'tb_notes',
    'tb_reading_time',
    'tb_themes',
    'tb_styles',
  ];

  static Future<void> restore(
    Database live,
    String backupPath, {
    required int version,
  }) async {
    final scratch = await Directory.systemTemp.createTemp('anx_restore_');
    try {
      final staged = await File(backupPath).copy('${scratch.path}/backup.db');
      final source = await databaseFactory.openDatabase(
        staged.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      late final Map<String, List<Map<String, Object?>>> rows;
      try {
        rows = await _readBackup(live, source, version);
      } finally {
        await source.close();
      }
      await live.transaction((txn) => _replaceRows(txn, rows));
    } finally {
      await _discard(scratch);
    }
  }

  static Future<Map<String, List<Map<String, Object?>>>> _readBackup(
    Database live,
    Database source,
    int version,
  ) async {
    if (await source.getVersion() != version) {
      throw const FormatException('Backup database version is not supported');
    }
    final integrity = await source.rawQuery('PRAGMA integrity_check');
    if (integrity.length != 1 || integrity.single.values.single != 'ok') {
      throw const FormatException('Backup database integrity check failed');
    }

    final result = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final columns = await _validateTable(live, source, table);
      result[table] = await source.query(table, columns: columns);
    }
    _validateRecords(result);
    return result;
  }

  static Future<List<String>> _validateTable(
    Database live,
    Database source,
    String table,
  ) async {
    final objects = await source.rawQuery(
      'SELECT type FROM sqlite_master WHERE name = ?',
      [table],
    );
    if (objects.length != 1 || objects.single['type'] != 'table') {
      throw FormatException('Missing backup table: $table');
    }

    final expected = await live.rawQuery('PRAGMA table_info($table)');
    final actual = await source.rawQuery('PRAGMA table_info($table)');
    final actualNames = actual.map((row) => row['name']).toSet();
    final columns = expected.map((row) => row['name'] as String).toList();
    if (columns.isEmpty || !actualNames.containsAll(columns)) {
      throw FormatException('Incomplete backup table: $table');
    }
    return columns;
  }

  static void _validateRecords(
      Map<String, List<Map<String, Object?>>> rows) {
    try {
      final groupRows = rows['tb_groups']!;
      final groups = <int, Map<String, Object?>>{};
      for (final row in groupRows) {
        final id = row['id'];
        if (id is! int || groups.containsKey(id)) {
          throw const FormatException('Invalid group identity');
        }
        groups[id] = row;
      }
      if (!groups.containsKey(0) || groups[0]!['parent_id'] != null) {
        throw const FormatException('Backup root group is missing or invalid');
      }
      _validateGroupHierarchy(groups);

      final bookIds = <int>{};
      for (final row in rows['tb_books']!) {
        final book = Book.fromDb(row);
        if (!bookIds.add(book.id)) {
          throw const FormatException('Duplicate book identity');
        }
        final group = groups[book.groupId];
        if (group == null) {
          throw const FormatException('Book references a missing group');
        }
        if (!book.isDeleted && (group['is_deleted'] as int? ?? 0) != 0) {
          throw const FormatException('Book references an invalid group');
        }
      }

      final noteKeys = <(int, String)>{};
      for (final row in rows['tb_notes']!) {
        final bookId = row['book_id'];
        final cfi = row['cfi'];
        if (bookId is! int || cfi is! String || cfi.trim().isEmpty) {
          throw const FormatException('Invalid note identity');
        }
        if (!bookIds.contains(bookId)) {
          throw const FormatException('Note references a missing book');
        }
        if (!noteKeys.add((bookId, cfi))) {
          throw const FormatException('Duplicate note identity');
        }
        BookNote.fromDb(row);
      }

      final readingKeys = <(int, String)>{};
      for (final row in rows['tb_reading_time']!) {
        final bookId = row['book_id'];
        final date = row['date'];
        final seconds = row['reading_time'];
        if (bookId is! int ||
            date is! String ||
            !_isCanonicalDate(date) ||
            seconds is! int ||
            seconds < 0) {
          throw const FormatException('Invalid reading-time record');
        }
        if (!bookIds.contains(bookId)) {
          throw const FormatException('Reading time references a missing book');
        }
        if (!readingKeys.add((bookId, date))) {
          throw const FormatException('Duplicate reading-time identity');
        }
        ReadingTime.fromDb(row);
      }
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Backup contains malformed business data', error);
    }
  }

  static void _validateGroupHierarchy(
      Map<int, Map<String, Object?>> groups) {
    for (final entry in groups.entries) {
      final parent = entry.value['parent_id'];
      if (parent != null && (parent is! int || !groups.containsKey(parent))) {
        throw const FormatException('Group references a missing parent');
      }

      final visited = <int>{};
      int? current = entry.key;
      while (current != null) {
        if (!visited.add(current)) {
          throw const FormatException('Group hierarchy contains a cycle');
        }
        final next = groups[current]?['parent_id'];
        current = next is int ? next : null;
      }
    }
  }

  static bool _isCanonicalDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
        parsed.year == int.parse(match.group(1)!) &&
        parsed.month == int.parse(match.group(2)!) &&
        parsed.day == int.parse(match.group(3)!);
  }

  static Future<void> _replaceRows(
    Transaction txn,
    Map<String, List<Map<String, Object?>>> rows,
  ) async {
    await txn.execute('PRAGMA defer_foreign_keys = ON');
    for (final table in tables.reversed) {
      await txn.delete(table);
    }
    for (final table in tables) {
      final batch = txn.batch();
      for (final row in rows[table]!) {
        batch.insert(table, row);
      }
      await batch.commit(noResult: true);
    }
  }

  static Future<void> _discard(Directory scratch) async {
    try {
      await scratch.delete(recursive: true);
    } catch (error) {
      AnxLog.warning('Backup staging cleanup failed: $error');
    }
  }
}
