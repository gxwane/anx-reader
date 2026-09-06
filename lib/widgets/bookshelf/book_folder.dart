import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/bookshelf_selection_provider.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/bookshelf/book_opened_folder.dart';
import 'package:anx_reader/widgets/common/container/outlined_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';

class BookFolder extends ConsumerStatefulWidget {
  const BookFolder({
    super.key,
    required this.books,
    this.onOpenBookSheet,
  });

  final List<Book> books;
  final void Function(Book)? onOpenBookSheet;

  @override
  ConsumerState<BookFolder> createState() => _BookFolderState();
}

class _BookFolderState extends ConsumerState<BookFolder> {
  bool willAcceptBook = false;

  @override
  Widget build(BuildContext context) {
    final folderStyle = context.watch<Prefs>().bookshelfFolderStyle;

    void onAcceptBook(DragTargetDetails<Book> details) {
      int targetGroupId;
      if (widget.books.first.groupId == 0) {
        ref.read(bookListProvider.notifier).updateBook(
            widget.books.first.copyWith(groupId: widget.books.first.id));
        targetGroupId = widget.books.first.id;
      } else {
        targetGroupId = widget.books.first.groupId;
      }
      ref.read(bookListProvider.notifier).moveBook(details.data, targetGroupId);
    }

    Widget scaleTransition(Widget child) {
      return willAcceptBook
          ? ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                CurvedAnimation(
                    parent: const AlwaysStoppedAnimation(0.5),
                    curve: Curves.easeInOut),
              ),
              child: child,
            )
          : child;
    }

    bool onWillAcceptBook(DragTargetDetails<Book>? details) {
      if (details?.data.id == widget.books.first.id) {
        return false;
      }
      willAcceptBook = details?.data != null;
      return details?.data != null;
    }

    void onLeaveBook(Book? book) {
      willAcceptBook = false;
    }

    void openFolder(String groupName) {
      showDialog(
        context: context,
        builder: (context) => BookOpenedFolder(
          books: widget.books,
          groupName: groupName,
        ),
      );
    }

    String groupName = ref.watch(groupDaoProvider).whenOrNull(
              data: (groups) => groups
                  .firstWhere((group) => group.id == widget.books.first.groupId,
                      orElse: () => TbGroup(id: -1, name: "..."))
                  .name,
            ) ??
        '???';

    final singleBookTarget = DragTarget<Book>(
      onAcceptWithDetails: (book) => onAcceptBook(book),
      onWillAcceptWithDetails: (data) => onWillAcceptBook(data),
      onLeave: (data) => onLeaveBook(data),
      builder: (context, candidateData, rejectedData) {
        return scaleTransition(
          BookItem(book: widget.books[0], onOpenBookSheet: widget.onOpenBookSheet),
        );
      },
    );

    final groupTarget = DragTarget<Book>(
      onAcceptWithDetails: (book) => onAcceptBook(book),
      onWillAcceptWithDetails: (data) => onWillAcceptBook(data),
      onLeave: (data) => onLeaveBook(data),
      builder: (context, candidateData, rejectedData) {
        int count = -1;

        Widget buildStackedPreview() {
          return Stack(
            children: [
              ...(widget.books.take(4).toList()).map((book) {
                count++;
                return Positioned.fill(
                  right: 0,
                  top: 30 - count * Prefs().bookCoverWidth * 0.12,
                  child: Transform.scale(
                    scale: 1 - (count * 0.08),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: BookCover(book: book),
                    ),
                  ),
                );
              }),
            ].reversed.toList(),
          );
        }

        Widget buildGridPreview() {
          final previewBooks = widget.books.take(4).toList();
          return OutlinedContainer(
            color: Colors.transparent,
            outlineColor: Theme.of(context).colorScheme.outlineVariant,
            padding: const EdgeInsets.all(6),
            radius: 10,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1 / 1.6,
                mainAxisSpacing: 16,
                crossAxisSpacing: 6,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                if (index >= previewBooks.length) {
                  return SizedBox.shrink();
                }
                final book = previewBooks[index];
                return BookCover(book: book);
              },
            ),
          );
        }

        Widget folderPreview;
        switch (folderStyle) {
          case BookshelfFolderStyle.grid2x2:
            folderPreview = buildGridPreview();
            break;
          case BookshelfFolderStyle.stacked:
            folderPreview = buildStackedPreview();
        }

        final isSelectionMode = ref.watch(
          bookshelfSelectionProvider.select((s) => s.isSelectionMode),
        );
        final folderBookIds = widget.books.map((b) => b.id).toList();
        final selectedFolderCount = ref.watch(
          bookshelfSelectionProvider.select(
            (s) => folderBookIds.where(s.selectedBookIds.contains).length,
          ),
        );
        final isAllFolderSelected = selectedFolderCount > 0 &&
            selectedFolderCount == folderBookIds.length;
        final isSomeFolderSelected =
            selectedFolderCount > 0 && !isAllFolderSelected;

        return scaleTransition(
          Column(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (isSelectionMode) {
                      ref
                          .read(bookshelfSelectionProvider.notifier)
                          .toggleFolder(folderBookIds);
                    } else {
                      openFolder(groupName);
                    }
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      folderPreview,
                      if (isSelectionMode)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isAllFolderSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : isSomeFolderSelected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withAlpha(200)
                                      : Colors.black.withAlpha(100),
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              isSomeFolderSelected
                                  ? Icons.remove
                                  : Icons.check,
                              size: 14,
                              color: (isAllFolderSelected ||
                                      isSomeFolderSelected)
                                  ? Colors.white
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 50,
                child: Text(
                  groupName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );

    return RepaintBoundary(
      child: widget.books.length == 1 ? singleBookTarget : groupTarget,
    );
  }
}
