import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/book_note.dart';

enum BookNoteRelocationFailure {
  invalidInput,
  missingNote,
  wrongBook,
  staleSource,
  occupiedTarget,
  duplicateTarget,
  conflictingInstruction,
  databaseFailure,
}

class BookNoteRelocationResult {
  const BookNoteRelocationResult._({
    required this.isSuccess,
    required this.updatedCount,
    this.failure,
  });

  const BookNoteRelocationResult.success(int updatedCount)
      : this._(isSuccess: true, updatedCount: updatedCount);

  const BookNoteRelocationResult.failure(BookNoteRelocationFailure failure)
      : this._(isSuccess: false, updatedCount: 0, failure: failure);

  final bool isSuccess;
  final int updatedCount;
  final BookNoteRelocationFailure? failure;

  Map<String, Object?> toJson() => {
        'success': isSuccess,
        'updatedCount': updatedCount,
        if (failure != null) 'failure': failure!.name,
      };
}

class _RelocationCommand {
  const _RelocationCommand({
    required this.id,
    required this.oldCfi,
    required this.newCfi,
    this.prefix,
    this.suffix,
  });

  final int id;
  final String oldCfi;
  final String newCfi;
  final String? prefix;
  final String? suffix;

  bool hasSameInstruction(_RelocationCommand other) =>
      oldCfi == other.oldCfi &&
      newCfi == other.newCfi &&
      prefix == other.prefix &&
      suffix == other.suffix;
}

class BookNoteDao extends BaseDao {
  BookNoteDao();

  static const String table = 'tb_notes';

  /// Annotation types for highlight/underline notes (excludes book reviews)
  static const List<String> annotationTypes = [
    'highlight',
    'underline',
    'bookmark'
  ];

  /// Helper to build type filter SQL
  static String get _typeFilter =>
      "type IN ('${annotationTypes.join("', '")}')";

  Future<int> save(BookNote bookNote) async {
    if (bookNote.cfi.trim().isEmpty) {
      throw ArgumentError.value(bookNote.cfi, 'cfi', 'CFI cannot be empty');
    }

    return transaction((txn) async {
      if (bookNote.id != null) {
        await txn.update(
          table,
          bookNote.toMap(),
          where: 'id = ?',
          whereArgs: [bookNote.id],
        );
        return bookNote.id!;
      }

      final existing = await txn.query(
        table,
        columns: const ['id'],
        where: 'book_id = ? AND cfi = ?',
        whereArgs: [bookNote.bookId, bookNote.cfi],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.single['id'] as int;
        bookNote.id = id;
        await txn.update(
          table,
          bookNote.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
        return id;
      }

      return txn.insert(table, bookNote.toMap());
    });
  }

  Future<List<BookNote>> selectBookNoteByCfiAndBookId(
      String cfi, int bookId) async {
    return queryList(
      table,
      mapper: BookNote.fromDb,
      where: 'cfi = ? AND book_id = ? AND $_typeFilter',
      whereArgs: [cfi, bookId],
      orderBy: 'update_time ASC',
    );
  }

  Future<List<BookNote>> selectBookNotesByBookId(int bookId) async {
    return queryList(
      table,
      mapper: BookNote.fromDb,
      where: 'book_id = ? AND $_typeFilter',
      whereArgs: [bookId],
      orderBy: 'update_time DESC',
    );
  }

  Future<void> updateBookNoteById(BookNote bookNote) async {
    await update(
      table,
      bookNote.toMap(),
      where: 'id = ?',
      whereArgs: [bookNote.id],
    );
  }

  /// Relocates one book's annotations atomically after validating the full batch.
  Future<BookNoteRelocationResult> relocateCfis(
    int bookId,
    List<Map<String, Object?>> items,
  ) async {
    if (bookId <= 0) {
      return const BookNoteRelocationResult.failure(
          BookNoteRelocationFailure.invalidInput);
    }
    if (items.isEmpty) {
      return const BookNoteRelocationResult.success(0);
    }

    final commandsById = <int, _RelocationCommand>{};
    final targetOwners = <String, int>{};
    for (final item in items) {
      final numericId = item['id'];
      final id = numericId is num ? numericId.toInt() : null;
      final oldCfi = item['oldCfi'] is String ? item['oldCfi'] as String : '';
      final newCfi = item['newCfi'] is String ? item['newCfi'] as String : '';
      if (id == null || id <= 0 || oldCfi.isEmpty || newCfi.isEmpty) {
        return const BookNoteRelocationResult.failure(
            BookNoteRelocationFailure.invalidInput);
      }
      final command = _RelocationCommand(
        id: id,
        oldCfi: oldCfi,
        newCfi: newCfi,
        prefix: item['prefix']?.toString(),
        suffix: item['suffix']?.toString(),
      );
      final previous = commandsById[id];
      if (previous != null && !previous.hasSameInstruction(command)) {
        return const BookNoteRelocationResult.failure(
            BookNoteRelocationFailure.conflictingInstruction);
      }
      commandsById[id] = command;

      final targetOwner = targetOwners[newCfi];
      if (targetOwner != null && targetOwner != id) {
        return const BookNoteRelocationResult.failure(
            BookNoteRelocationFailure.duplicateTarget);
      }
      targetOwners[newCfi] = id;
    }

    final commands = commandsById.values.toList(growable: false);

    try {
      return await transaction((txn) async {
        final placeholders = List.filled(commands.length, '?').join(',');
        final rows = await txn.query(
          table,
          where: 'id IN ($placeholders)',
          whereArgs: commands.map((command) => command.id).toList(),
        );
        final rowsById = {for (final row in rows) row['id'] as int: row};

        for (final command in commands) {
          final row = rowsById[command.id];
          if (row == null) {
            return const BookNoteRelocationResult.failure(
                BookNoteRelocationFailure.missingNote);
          }
          if (row['book_id'] != bookId) {
            return const BookNoteRelocationResult.failure(
                BookNoteRelocationFailure.wrongBook);
          }
          if (row['cfi'] != command.oldCfi) {
            return const BookNoteRelocationResult.failure(
                BookNoteRelocationFailure.staleSource);
          }
        }

        for (final command in commands) {
          final occupied = await txn.query(
            table,
            columns: const ['id'],
            where: 'book_id = ? AND cfi = ? AND id <> ?',
            whereArgs: [bookId, command.newCfi, command.id],
            limit: 1,
          );
          if (occupied.isNotEmpty) {
            return const BookNoteRelocationResult.failure(
                BookNoteRelocationFailure.occupiedTarget);
          }
        }

        final now = DateTime.now().toUtc().toIso8601String();
        for (final command in commands) {
          final changed = await txn.update(
            table,
            {
              'cfi': command.newCfi,
              if (command.prefix != null)
                'context_prefix': command.prefix,
              if (command.suffix != null)
                'context_suffix': command.suffix,
              'update_time': now,
            },
            where: 'id = ? AND book_id = ? AND cfi = ?',
            whereArgs: [command.id, bookId, command.oldCfi],
          );
          if (changed != 1) {
            throw StateError('Annotation changed during relocation');
          }
        }

        return BookNoteRelocationResult.success(commands.length);
      });
    } catch (_) {
      return const BookNoteRelocationResult.failure(
          BookNoteRelocationFailure.databaseFailure);
    }
  }

  Future<BookNote> selectBookNoteById(int id) async {
    final note = await querySingle(
      table,
      mapper: BookNote.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (note == null) {
      throw StateError('Book note with id $id not found');
    }

    return note;
  }

  Future<List<Map<String, dynamic>>> selectAllBookIdAndNotes() async {
    return rawQueryList(
      'SELECT book_id, COUNT(id) AS number_of_notes, MAX(update_time) AS latest_time FROM $table WHERE $_typeFilter GROUP BY book_id ORDER BY MAX(update_time) DESC',
      mapper: (row) => <String, dynamic>{
        'bookId': row['book_id'] as int? ?? 0,
        'numberOfNotes': row['number_of_notes'] as int? ?? 0,
        'latestTime': row['latest_time'] as String? ?? '',
      },
    ).then((rows) => rows.where((element) => element['bookId'] != 0).toList());
  }

  Future<Map<String, int>> selectNumberOfNotesAndBooks() async {
    final result = await rawQuerySingle(
      'SELECT COUNT(id) AS number_of_notes, COUNT(DISTINCT book_id) AS number_of_books FROM $table WHERE $_typeFilter',
      mapper: (row) => <String, int>{
        'numberOfNotes': row['number_of_notes'] as int? ?? 0,
        'numberOfBooks': row['number_of_books'] as int? ?? 0,
      },
    );

    return result ?? const {'numberOfNotes': 0, 'numberOfBooks': 0};
  }

  Future<void> deleteBookNoteById(int id) async {
    await delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllNotesByBookId(int bookId) {
    return delete(
      table,
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<BookNote>> searchBookNotes(String keyword) {
    final query = keyword.trim();
    if (query.isEmpty) {
      return Future.value(const []);
    }
    return searchBookNotesAdvanced(keyword: query, types: annotationTypes);
  }

  Future<List<BookNote>> searchBookNotesAdvanced({
    String? keyword,
    int? bookId,
    DateTime? from,
    DateTime? to,
    int? limit,
    List<String>? types,
  }) async {
    final where = <String>[];
    final whereArgs = <Object?>[];
    final query = keyword?.trim();

    // Filter by types (defaults to annotation types if not specified)
    final filterTypes = types ?? annotationTypes;
    if (filterTypes.isNotEmpty) {
      where.add("type IN ('${filterTypes.join("', '")}')");
    }

    if (query != null && query.isNotEmpty) {
      where.add('(content LIKE ? OR reader_note LIKE ? OR chapter LIKE ?)');
      final pattern = '%$query%';
      whereArgs.addAll([pattern, pattern, pattern]);
    }

    if (bookId != null) {
      where.add('book_id = ?');
      whereArgs.add(bookId);
    }

    if (from != null) {
      where.add('update_time >= ?');
      whereArgs.add(from.toIso8601String());
    }

    if (to != null) {
      where.add('update_time <= ?');
      whereArgs.add(to.toIso8601String());
    }

    return queryList(
      table,
      mapper: BookNote.fromDb,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'update_time DESC',
      limit: limit,
    );
  }

  Future<BookNote?> selectRandomNote() async {
    return rawQuerySingle(
      'SELECT * FROM $table WHERE $_typeFilter ORDER BY RANDOM() LIMIT 1',
      mapper: BookNote.fromDb,
    );
  }

  Future<void> migrateTemporaryNotes(int newBookId) async {
    final db = await database;
    await db.update(
      table,
      {'book_id': newBookId},
      where: 'book_id = ?',
      whereArgs: [-1],
    );
  }

  Future<void> clearTemporaryNotes() async {
    final db = await database;
    await db.delete(
      table,
      where: 'book_id = ?',
      whereArgs: [-1],
    );
  }
}

final bookNoteDao = BookNoteDao();
