import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/book_note.dart';

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
      "type IN ('${annotationTypes.join("', '")}') AND (is_deleted = 0 OR is_deleted IS NULL)";

  /// In-memory dirty tracker for book notes to enable event-driven micro-sync.
  static final Set<int> _dirtyBookIds = {};

  static void markDirty(int bookId) => _dirtyBookIds.add(bookId);
  static bool isDirty(int bookId) => _dirtyBookIds.contains(bookId);
  static void markClean(int bookId) => _dirtyBookIds.remove(bookId);
  static void clearAllDirty() => _dirtyBookIds.clear();

  Future<int> save(BookNote bookNote) async {
    markDirty(bookNote.bookId);
    if (bookNote.id != null) {
      await updateBookNoteById(bookNote);
      return bookNote.id!;
    }

    final duplicates =
        await selectBookNoteByCfiAndBookId(bookNote.cfi, bookNote.bookId);
    if (duplicates.isNotEmpty) {
      bookNote.id = duplicates.last.id;
      await updateBookNoteById(bookNote);
      return bookNote.id!;
    }

    return insert(table, bookNote.toMap());
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
    markDirty(bookNote.bookId);
    await update(
      table,
      bookNote.toMap(),
      where: 'id = ?',
      whereArgs: [bookNote.id],
    );
  }

  /// Atomically updates relocated notes to new CFIs and creates tombstones
  /// for old CFIs in a single transaction, preventing WebDAV zombie resurrection.
  Future<void> batchUpdateCfiWithTombstones(
    int bookId,
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return;
    markDirty(bookId);
    final now = DateTime.now().toUtc().toIso8601String();

    await transaction((txn) async {
      for (final item in items) {
        final id = (item['id'] as num?)?.toInt();
        if (id == null) continue;
        final oldCfi = item['oldCfi']?.toString() ?? '';
        final newCfi = item['newCfi']?.toString() ?? '';
        final prefix = item['prefix']?.toString();
        final suffix = item['suffix']?.toString();
        if (newCfi.isEmpty) continue;

        final originalRows = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (originalRows.isEmpty) continue;
        final original = originalRows.first;

        await txn.update(
          table,
          {
            'cfi': newCfi,
            if (prefix != null) 'context_prefix': prefix,
            if (suffix != null) 'context_suffix': suffix,
            'update_time': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        if (oldCfi.isNotEmpty && oldCfi != newCfi) {
          await txn.insert(
            table,
            {
              'book_id': original['book_id'] ?? bookId,
              'content': original['content'] ?? '',
              'cfi': oldCfi,
              'chapter': original['chapter'] ?? '',
              'type': original['type'] ?? 'highlight',
              'color': original['color'] ?? '',
              'is_deleted': 1,
              'create_time': original['create_time'],
              'update_time': now,
            },
          );
        }
      }
    });
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
    try {
      final note = await selectBookNoteById(id);
      markDirty(note.bookId);
    } catch (_) {}
    await update(
      table,
      {
        'is_deleted': 1,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllNotesByBookId(int bookId) async {
    markDirty(bookId);
    return await update(
      table,
      {
        'is_deleted': 1,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'book_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
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

    where.add('(is_deleted = 0 OR is_deleted IS NULL)');

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
}

final bookNoteDao = BookNoteDao();
