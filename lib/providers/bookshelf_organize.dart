import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_organize_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookshelfOrganizeServiceProvider = Provider(
  (ref) => BookshelfOrganizeController(ref, BookshelfOrganizeService()),
);

class BookshelfOrganizeController {
  BookshelfOrganizeController(this._ref, this._service);

  final Ref _ref;
  final BookshelfOrganizeService _service;

  Future<void> applyPlan(BookshelfOrganizePlan plan) async {
    await _service.applyPlan(plan);
    await _ref.read(bookListProvider.notifier).refresh();
    await _ref.read(groupDaoProvider.notifier).refresh();
  }
}
