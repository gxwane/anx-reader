import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_group.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan_group.dart';

class BookshelfOrganizeService {
  Future<void> applyPlan(BookshelfOrganizePlan plan) async {
    final ids = plan.affectedBookIds.toSet();
    final books = await bookDao.selectBooksByIds(ids.toList());
    final assignments = {for (final book in books) book.id: book.groupId};
    if (!assignments.keys.toSet().containsAll(ids)) {
      throw StateError('An organize plan references a missing book');
    }
    await bookGroupDao.validateHierarchy();

    for (final group in plan.groups) {
      await _prepareGroup(group);
      await _move(
        group.books.map((book) => book.bookId),
        group.groupId,
        assignments,
      );
    }
    await _move(
      plan.ungroupedBooks.map((book) => book.bookId),
      0,
      assignments,
    );
    for (final id in plan.cleanupGroupIds.where((id) => id > 0)) {
      await bookGroupDao.softDeleteIfEmpty(id);
    }
  }

  Future<void> _prepareGroup(BookshelfOrganizePlanGroup group) async {
    if (group.groupId <= 0) {
      throw ArgumentError.value(group.groupId, 'groupId', 'Invalid target');
    }
    final existing = await bookGroupDao.getGroup(group.groupId);
    if (!group.createNew && existing == null) {
      throw StateError('An organize plan references a missing group');
    }
    await bookGroupDao.ensure(group.groupId);
    final name = group.proposedName ?? group.currentName ?? 'New group';
    await bookGroupDao.rename(group.groupId, name);
  }

  Future<void> _move(
    Iterable<int> ids,
    int target,
    Map<int, int> assignments,
  ) async {
    final changed = ids.where((id) => assignments[id] != target).toSet();
    await bookDao.batchUpdateGroup(changed.toList(), target);
    for (final id in changed) {
      assignments[id] = target;
    }
  }
}
