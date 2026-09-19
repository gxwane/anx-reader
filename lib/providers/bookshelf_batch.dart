import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/last_read_book_provider.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_batch_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookshelfBatchControllerProvider = Provider(
  (ref) => BookshelfBatchController(ref, BookshelfBatchService()),
);

class BookshelfBatchController {
  BookshelfBatchController(this._ref, this._service);

  final Ref _ref;
  final BookshelfBatchService _service;

  Future<void> batchChangeStatus(
      List<Book> books, ReadingStatus newStatus) async {
    await _service.batchChangeStatus(books, newStatus);
    await _ref.read(bookListProvider.notifier).refresh();
  }

  Future<void> batchMoveGroup(List<int> bookIds, int targetGroupId) async {
    await _service.batchMoveGroup(bookIds, targetGroupId);
    await _ref.read(bookListProvider.notifier).refresh();
    await _ref.read(groupDaoProvider.notifier).refresh();
  }

  Future<void> batchCreateGroupAndMove(
      List<int> bookIds, String groupName) async {
    await _service.batchCreateGroupAndMove(bookIds, groupName);
    await _ref.read(bookListProvider.notifier).refresh();
    await _ref.read(groupDaoProvider.notifier).refresh();
  }

  Future<void> batchDeleteBooks(List<Book> books) async {
    await _service.batchDeleteBooks(books);
    await _ref.read(bookListProvider.notifier).refresh();
    _ref.read(lastReadBookProvider.notifier).refresh();
    _ref.read(syncStatusProvider.notifier).refresh();
  }

  Future<int> batchReleaseSpace(List<Book> books) async {
    var released = 0;
    for (final book in books) {
      try {
        await _ref.read(syncProvider.notifier).releaseBook(book);
        released++;
      } catch (error) {
        AnxLog.warning('batchReleaseSpace: failed for ${book.title}: $error');
      }
    }
    _ref.read(syncStatusProvider.notifier).refresh();
    return released;
  }
}
