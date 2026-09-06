import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/last_read_book_provider.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookshelfBatchService {
  BookshelfBatchService(this._ref);

  final WidgetRef _ref;

  Future<void> batchChangeStatus(List<Book> books, ReadingStatus newStatus) async {
    if (books.isEmpty) return;
    final bookIds = books.map((b) => b.id).toList();
    await bookDao.batchUpdateStatus(bookIds, newStatus);
    await _ref.read(bookListProvider.notifier).refresh();
  }

  Future<void> batchMoveGroup(List<int> bookIds, int targetGroupId) async {
    if (bookIds.isEmpty) return;
    await bookDao.batchUpdateGroup(bookIds, targetGroupId);
    if (targetGroupId != 0) {
      await _ref.read(groupDaoProvider.notifier).insertGroup(targetGroupId);
    }
    await _ref.read(bookListProvider.notifier).refresh();
  }

  Future<void> batchCreateGroupAndMove(List<int> bookIds, String groupName) async {
    if (bookIds.isEmpty) return;
    final targetGroupId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final groupNotifier = _ref.read(groupDaoProvider.notifier);
    await groupNotifier.insertGroup(targetGroupId);
    final group = await groupNotifier.getGroup(targetGroupId);
    if (group != null) {
      await groupNotifier.updateGroup(group.copyWith(name: groupName));
    }
    await batchMoveGroup(bookIds, targetGroupId);
  }

  Future<void> batchDeleteBooks(List<Book> books) async {
    if (books.isEmpty) return;
    final bookIds = books.map((b) => b.id).toList();
    await bookDao.batchSoftDelete(bookIds);

    for (final book in books) {
      try {
        final bookFile = File(book.fileFullPath);
        if (await bookFile.exists()) {
          await bookFile.delete();
        }
      } catch (e) {
        AnxLog.warning('batchDeleteBooks: failed to delete file for ${book.title}: $e');
      }
      try {
        final coverFile = File(book.coverFullPath);
        if (await coverFile.exists()) {
          await coverFile.delete();
        }
      } catch (e) {
        AnxLog.warning('batchDeleteBooks: failed to delete cover for ${book.title}: $e');
      }
    }

    await _ref.read(bookListProvider.notifier).refresh();
    _ref.read(lastReadBookProvider.notifier).refresh();
    _ref.read(syncStatusProvider.notifier).refresh();
  }

  Future<int> batchReleaseSpace(List<Book> books) async {
    if (books.isEmpty) return 0;
    int releasedCount = 0;
    for (final book in books) {
      try {
        await _ref.read(syncProvider.notifier).releaseBook(book);
        releasedCount++;
      } catch (e) {
        AnxLog.warning('batchReleaseSpace: failed for ${book.title}: $e');
      }
    }
    _ref.read(syncStatusProvider.notifier).refresh();
    return releasedCount;
  }
}
