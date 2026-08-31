import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/book_sync_status.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookItem extends ConsumerWidget {
  const BookItem({
    super.key,
    required this.book,
    this.onOpenBookSheet,
  });

  final Book book;
  final void Function(Book)? onOpenBookSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> handleLongPress(BuildContext context) async {
      showModalBottomSheet(
          context: context,
          builder: (BuildContext context) {
            return BookBottomSheet(book: book);
          });
    }

    Future<void> showDesktopMenu(
        BuildContext context, Offset globalPosition) async {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (overlay == null) return;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      );

      final result = await showMenu<String>(
        context: context,
        position: position,
        items: [
          PopupMenuItem(
            value: 'open',
            child: Row(
              children: [
                const Icon(Icons.menu_book_outlined, size: 18),
                const SizedBox(width: 10),
                Text(L10n.of(context).navBarBookshelf),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'detail',
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 10),
                Text(L10n.of(context).notesPageDetail),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'status_unread',
            child: Row(
              children: [
                Icon(
                  Icons.bookmark_border_outlined,
                  size: 18,
                  color: book.status == ReadingStatus.unread
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  L10n.of(context).readingStatusMarkUnread,
                  style: TextStyle(
                    fontWeight: book.status == ReadingStatus.unread
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'status_reading',
            child: Row(
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 18,
                  color: book.status == ReadingStatus.reading
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  L10n.of(context).readingStatusMarkReading,
                  style: TextStyle(
                    fontWeight: book.status == ReadingStatus.reading
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'status_finished',
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: book.status == ReadingStatus.finished
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  L10n.of(context).readingStatusMarkFinished,
                  style: TextStyle(
                    fontWeight: book.status == ReadingStatus.finished
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'status_abandoned',
            child: Row(
              children: [
                Icon(
                  Icons.cancel_outlined,
                  size: 18,
                  color: book.status == ReadingStatus.abandoned
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  L10n.of(context).readingStatusMarkAbandoned,
                  style: TextStyle(
                    fontWeight: book.status == ReadingStatus.abandoned
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

      if (!context.mounted || result == null) return;

      if (result == 'open') {
        pushToReadingPage(ref, context, book);
      } else if (result == 'detail') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => BookDetail(book: book)),
        );
      } else if (result.startsWith('status_')) {
        ReadingStatus newStatus;
        switch (result) {
          case 'status_unread':
            newStatus = ReadingStatus.unread;
            break;
          case 'status_reading':
            newStatus = ReadingStatus.reading;
            break;
          case 'status_finished':
            newStatus = ReadingStatus.finished;
            break;
          case 'status_abandoned':
            newStatus = ReadingStatus.abandoned;
            break;
          default:
            return;
        }

        final now = DateTime.now();
        DateTime? start = book.startReadingTime;
        DateTime? finish = book.finishReadingTime;
        int count = book.readCount;

        if (newStatus == ReadingStatus.reading) {
          start ??= now;
        } else if (newStatus == ReadingStatus.finished) {
          finish = now;
          if (book.status != ReadingStatus.finished) {
            count += 1;
          }
        }

        await bookDao.updateBook(book.copyWith(
          status: newStatus,
          startReadingTime: start,
          finishReadingTime: finish,
          readCount: count,
          updateTime: now,
        ));
        ref.read(bookListProvider.notifier).refresh();
      }
    }

    BookSyncStatusEnum bookSyncStatus =
        ref.watch(syncStatusProvider).whenOrNull(data: (data) {
              if (data.downloading.contains(book.id)) {
                return BookSyncStatusEnum.downloading;
              } else if (data.uploading.contains(book.id)) {
                return BookSyncStatusEnum.uploading;
              } else if (data.localOnly.contains(book.id)) {
                return BookSyncStatusEnum.localOnly;
              } else if (data.remoteOnly.contains(book.id)) {
                return BookSyncStatusEnum.remoteOnly;
              } else if (data.both.contains(book.id)) {
                return BookSyncStatusEnum.both;
              } else if (data.nonExistent.contains(book.id)) {
                return BookSyncStatusEnum.nonExistent;
              } else {
                return BookSyncStatusEnum.checking;
              }
            }) ??
            BookSyncStatusEnum.checking;

    return GestureDetector(
      onTap: () {
        pushToReadingPage(ref, context, book);
      },
      onLongPress: () {
        final cb = onOpenBookSheet;
        if (cb != null) {
          cb(book);
        } else {
          handleLongPress(context);
        }
      },
      onSecondaryTapUp: (details) {
        if (AnxPlatform.isDesktop) {
          showDesktopMenu(context, details.globalPosition);
        } else {
          final cb = onOpenBookSheet;
          if (cb != null) {
            cb(book);
          } else {
            handleLongPress(context);
          }
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: book.coverFullPath,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    if (!Prefs().eInkMode)
                      BoxShadow(
                        color: Colors.grey.withAlpha(100),
                        spreadRadius: 5,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: BookCover(book: book),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (Prefs().webdavStatus)
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: BookSyncStatusIcon(
                        syncStatus: bookSyncStatus,
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      book.author,
                      maxLines: 1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w300,
                        fontSize: 9,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    book.status == ReadingStatus.finished
                        ? L10n.of(context).readingStatusFinished
                        : book.status == ReadingStatus.abandoned
                            ? L10n.of(context).readingStatusAbandoned
                            : "${(book.readingPercentage * 100).toStringAsFixed(0)}%",
                    style: TextStyle(
                      fontWeight: book.status == ReadingStatus.finished
                          ? FontWeight.bold
                          : FontWeight.w300,
                      fontSize: 9,
                      color: book.status == ReadingStatus.finished
                          ? Theme.of(context).colorScheme.primary
                          : book.status == ReadingStatus.abandoned
                              ? Colors.grey
                              : null,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
