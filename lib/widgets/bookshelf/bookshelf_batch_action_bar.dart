import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/bookshelf_selection_provider.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_batch_service.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookshelfBatchActionBar extends ConsumerWidget {
  const BookshelfBatchActionBar({super.key});

  Future<void> _showStatusSheet(
    BuildContext context,
    WidgetRef ref,
    List<Book> selectedBooks,
  ) async {
    final items = [
      (
        ReadingStatus.unread,
        L10n.of(context).readingStatusUnread,
        Icons.bookmark_border_outlined,
      ),
      (
        ReadingStatus.reading,
        L10n.of(context).readingStatusReading,
        Icons.auto_stories_outlined,
      ),
      (
        ReadingStatus.finished,
        L10n.of(context).readingStatusFinished,
        Icons.check_circle_outline,
      ),
      (
        ReadingStatus.abandoned,
        L10n.of(context).readingStatusAbandoned,
        Icons.cancel_outlined,
      ),
    ];

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  L10n.of(context).bookshelfBatchChangeStatus,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...items.map((item) {
                return ListTile(
                  leading: Icon(item.$3),
                  title: Text(item.$2),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final service = BookshelfBatchService(ref);
                    await service.batchChangeStatus(selectedBooks, item.$1);
                    ref.read(bookshelfSelectionProvider.notifier).exitSelectionMode();
                    if (context.mounted) {
                      AnxToast.show(
                        L10n.of(context)
                            .bookshelfBatchStatusUpdated(selectedBooks.length),
                      );
                    }
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showMoveGroupDialog(
    BuildContext context,
    WidgetRef ref,
    List<Book> selectedBooks,
  ) async {
    final groupsAsync = await ref.read(groupDaoProvider.future);
    final availableGroups =
        groupsAsync.where((g) => g.id != 0 && g.isDeleted == 0).toList();

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L10n.of(context).bookshelfBatchMoveToGroup),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: Text(L10n.of(context).bookshelfRemoveFromGroup),
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    final service = BookshelfBatchService(ref);
                    await service.batchMoveGroup(
                      selectedBooks.map((b) => b.id).toList(),
                      0,
                    );
                    ref
                        .read(bookshelfSelectionProvider.notifier)
                        .exitSelectionMode();
                    if (context.mounted) {
                      AnxToast.show(
                        L10n.of(context)
                            .bookshelfBatchMovedSuccess(selectedBooks.length),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: Text(L10n.of(context).bookshelfNewFolder),
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    await _showCreateFolderDialog(context, ref, selectedBooks);
                  },
                ),
                if (availableGroups.isNotEmpty) const Divider(),
                ...availableGroups.map((group) {
                  return ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(group.name),
                    onTap: () async {
                      Navigator.pop(dialogContext);
                      final service = BookshelfBatchService(ref);
                      await service.batchMoveGroup(
                        selectedBooks.map((b) => b.id).toList(),
                        group.id,
                      );
                      ref
                          .read(bookshelfSelectionProvider.notifier)
                          .exitSelectionMode();
                      if (context.mounted) {
                        AnxToast.show(
                          L10n.of(context)
                              .bookshelfBatchMovedSuccess(selectedBooks.length),
                        );
                      }
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(L10n.of(context).commonCancel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateFolderDialog(
    BuildContext context,
    WidgetRef ref,
    List<Book> selectedBooks,
  ) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L10n.of(context).bookshelfNewFolder),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: L10n.of(context).bookshelfBatchMoveToGroup,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(L10n.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogContext);
                final service = BookshelfBatchService(ref);
                await service.batchCreateGroupAndMove(
                  selectedBooks.map((b) => b.id).toList(),
                  name,
                );
                ref
                    .read(bookshelfSelectionProvider.notifier)
                    .exitSelectionMode();
                if (context.mounted) {
                  AnxToast.show(
                    L10n.of(context)
                        .bookshelfBatchMovedSuccess(selectedBooks.length),
                  );
                }
              },
              child: Text(L10n.of(context).commonConfirm),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleReleaseSpace(
    BuildContext context,
    WidgetRef ref,
    List<Book> selectedBooks,
  ) async {
    final service = BookshelfBatchService(ref);
    final count = await service.batchReleaseSpace(selectedBooks);
    ref.read(bookshelfSelectionProvider.notifier).exitSelectionMode();
    if (context.mounted) {
      AnxToast.show(L10n.of(context).bookshelfBatchReleasedSuccess(count));
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    List<Book> selectedBooks,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            L10n.of(context).bookshelfBatchDeleteConfirm(selectedBooks.length),
          ),
          content: Text(L10n.of(context).bookshelfBatchDeleteNotice),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(L10n.of(context).commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                final service = BookshelfBatchService(ref);
                await service.batchDeleteBooks(selectedBooks);
                ref
                    .read(bookshelfSelectionProvider.notifier)
                    .exitSelectionMode();
              },
              child: Text(
                L10n.of(context).bookshelfBatchDelete,
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedBookIds = ref.watch(
      bookshelfSelectionProvider.select((s) => s.selectedBookIds),
    );
    final booksAsync = ref.watch(bookListProvider);
    final allBooks =
        booksAsync.valueOrNull?.expand((group) => group).toList() ?? [];
    final selectedBooks =
        allBooks.where((b) => selectedBookIds.contains(b.id)).toList();
    final hasSelection = selectedBooks.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer.withAlpha(240),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.bookmark_border_outlined,
                label: L10n.of(context).bookshelfBatchChangeStatus,
                isEnabled: hasSelection,
                onTap: () => _showStatusSheet(context, ref, selectedBooks),
              ),
              _ActionButton(
                icon: Icons.folder_outlined,
                label: L10n.of(context).bookshelfBatchMoveToGroup,
                isEnabled: hasSelection,
                onTap: () => _showMoveGroupDialog(context, ref, selectedBooks),
              ),
              _ActionButton(
                icon: Icons.cloud_upload_outlined,
                label: L10n.of(context).bookshelfBatchReleaseSpace,
                isEnabled: hasSelection,
                onTap: () => _handleReleaseSpace(context, ref, selectedBooks),
              ),
              _ActionButton(
                icon: Icons.delete_outline,
                label: L10n.of(context).bookshelfBatchDelete,
                color: Theme.of(context).colorScheme.error,
                isEnabled: hasSelection,
                onTap: () => _handleDelete(context, ref, selectedBooks),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isEnabled,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool isEnabled;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurface;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isEnabled ? onTap : null,
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.38,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: effectiveColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: effectiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
