import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_group.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/utils/log/common.dart';

class BookshelfBatchService {
  Future<void> batchChangeStatus(
      List<Book> books, ReadingStatus newStatus) async {
    if (books.isEmpty) return;
    await bookDao.batchUpdateStatus(books.map((book) => book.id).toList(), newStatus);
  }

  Future<void> batchMoveGroup(List<int> bookIds, int targetGroupId) async {
    if (bookIds.isEmpty) return;
    if (targetGroupId != 0) await bookGroupDao.ensure(targetGroupId);
    await bookDao.batchUpdateGroup(bookIds, targetGroupId);
  }

  Future<int> batchCreateGroupAndMove(
      List<int> bookIds, String groupName) async {
    if (bookIds.isEmpty) return 0;
    var target = DateTime.now().millisecondsSinceEpoch;
    while (await bookGroupDao.getGroup(target) != null) {
      target++;
    }
    await bookGroupDao.ensure(target);
    await bookGroupDao.rename(target, groupName);
    await batchMoveGroup(bookIds, target);
    return target;
  }

  Future<void> batchDeleteBooks(List<Book> books) async {
    if (books.isEmpty) return;
    await bookDao.batchSoftDelete(books.map((book) => book.id).toList());
    for (final book in books) {
      await _deleteIfPresent(book.fileFullPath, book.title, 'book');
      await _deleteIfPresent(book.coverFullPath, book.title, 'cover');
    }
  }

  Future<void> _deleteIfPresent(
      String path, String title, String kind) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      AnxLog.warning(
          'batchDeleteBooks: failed to delete $kind for $title: $error');
    }
  }
}
