import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';

class BookDao extends BaseDao {
  BookDao();

  static const String table = 'tb_books';

  Future<int> save(Book book) async {
    if (book.id != -1) {
      await updateBook(book);
      return book.id;
    }
    return insert(table, book.toMap());
  }

  Future<int> insertBook(Book book) => save(book);

  Future<void> updateBook(Book book) async {
    book.updateTime = DateTime.now();
    await update(
      table,
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  Future<List<Book>> selectBooks({bool includeDeleted = true}) {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectNotDeleteBooks() {
    return selectBooks(includeDeleted: false);
  }

  Future<Book> selectBookById(int id) async {
    final book = await querySingle(
      table,
      mapper: Book.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (book == null) {
      throw StateError('Book with id $id not found');
    }
    return book;
  }

  Future<List<String>> getCurrentBooks() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.filePath).toList(growable: false);
  }

  Future<List<String>> getCurrentCover() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.coverPath).toList(growable: false);
  }

  Future<List<Book>> selectAllBooks() {
    return selectBooks();
  }

  Future<Book?> getBookByMd5(String md5) {
    return querySingle(
      table,
      mapper: Book.fromDb,
      where: 'file_md5 = ?',
      whereArgs: [md5],
    );
  }

  Future<List<Book>> searchBooks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    return queryList(
      table,
      mapper: Book.fromDb,
      where: 'is_deleted = 0 AND (title LIKE ? OR author LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectBooksByIds(
    List<int> ids, {
    bool includeDeleted = true,
  }) async {
    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    final whereClause = includeDeleted
        ? 'id IN ($placeholders)'
        : 'is_deleted = 0 AND id IN ($placeholders)';
    return rawQueryList(
      'SELECT * FROM $table WHERE $whereClause',
      arguments: ids,
      mapper: Book.fromDb,
    );
  }

  Future<void> updateBookMd5(int bookId, String md5) {
    return update(
      table,
      {
        'file_md5': md5,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<Book>> getBooksWithoutMd5() {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: "is_deleted = 0 AND (file_md5 IS NULL OR file_md5 = '')",
      orderBy: 'update_time DESC',
    );
  }

  Future<void> batchUpdateStatus(
    List<int> bookIds,
    ReadingStatus status,
  ) async {
    if (bookIds.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(bookIds.length, '?').join(',');
    final db = await database;

    await db.transaction((txn) async {
      switch (status) {
        case ReadingStatus.unread:
          await txn.rawUpdate(
            '''
            UPDATE $table
            SET reading_status = ?, update_time = ?
            WHERE id IN ($placeholders)
            ''',
            [status.value, now, ...bookIds],
          );
          break;
        case ReadingStatus.reading:
          await txn.rawUpdate(
            '''
            UPDATE $table
            SET reading_status = ?,
                start_reading_time = COALESCE(start_reading_time, ?),
                update_time = ?
            WHERE id IN ($placeholders)
            ''',
            [status.value, now, now, ...bookIds],
          );
          break;
        case ReadingStatus.finished:
          await txn.rawUpdate(
            '''
            UPDATE $table
            SET reading_status = ?,
                finish_reading_time = ?,
                read_count = CASE WHEN reading_status = ? THEN read_count ELSE read_count + 1 END,
                update_time = ?
            WHERE id IN ($placeholders)
            ''',
            [status.value, now, status.value, now, ...bookIds],
          );
          break;
        case ReadingStatus.abandoned:
          await txn.rawUpdate(
            '''
            UPDATE $table
            SET reading_status = ?, update_time = ?
            WHERE id IN ($placeholders)
            ''',
            [status.value, now, ...bookIds],
          );
          break;
      }
    });
  }

  Future<void> batchUpdateGroup(
    List<int> bookIds,
    int groupId,
  ) async {
    if (bookIds.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(bookIds.length, '?').join(',');
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE $table
        SET group_id = ?, update_time = ?
        WHERE id IN ($placeholders)
        ''',
        [groupId, now, ...bookIds],
      );
    });
  }

  Future<void> batchSoftDelete(List<int> bookIds) async {
    if (bookIds.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(bookIds.length, '?').join(',');
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE $table
        SET is_deleted = 1, update_time = ?
        WHERE id IN ($placeholders)
        ''',
        [now, ...bookIds],
      );
    });
  }
}

final bookDao = BookDao();
