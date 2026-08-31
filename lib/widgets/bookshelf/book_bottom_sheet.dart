import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/share_file.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:path/path.dart' as p;

class BookBottomSheet extends ConsumerWidget {
  const BookBottomSheet({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> handleDelete(BuildContext context) async {
      Navigator.pop(context);
      await bookDao.updateBook(Book(
        id: book.id,
        title: book.title,
        coverPath: book.coverPath,
        filePath: book.filePath,
        lastReadPosition: book.lastReadPosition,
        readingPercentage: book.readingPercentage,
        author: book.author,
        isDeleted: true,
        description: book.description,
        rating: book.rating,
        md5: book.md5,
        createTime: book.createTime,
        updateTime: DateTime.now(),
      ));
      ref.read(bookListProvider.notifier).refresh();
      File(book.fileFullPath).delete();
      File(book.coverFullPath).delete();
    }

    void handleDetail(BuildContext context) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookDetail(book: book),
        ),
      );
    }

    void handleUpload(BuildContext context) {
      Future<void> core() async {
        await ref.read(syncProvider.notifier).releaseBook(book);
        ref.read(syncStatusProvider.notifier).refresh();
      }

      if (Prefs().shouldShowHint(HintKey.releaseLocalSpace)) {
        SmartDialog.show(
          builder: (context) => AlertDialog(
            title: Text(L10n.of(context).bookSyncStatusReleaseSpaceDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context).bookSyncStatusReleaseSpaceDialogContent),
                Row(
                  children: [
                    StatefulBuilder(builder: (context, setState) {
                      return Checkbox(
                          value: !Prefs()
                              .shouldShowHint(HintKey.releaseLocalSpace),
                          onChanged: (value) {
                            value = !(value ?? false);
                            Prefs()
                                .setShowHint(HintKey.releaseLocalSpace, value);
                            setState(() {});
                          });
                    }),
                    Text(L10n.of(context).bookSyncStatusDoNotShowAgain),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                },
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                  core();
                },
                child: Text(L10n.of(context).commonConfirm),
              ),
            ],
          ),
        );
      } else {
        ref.read(syncProvider.notifier).releaseBook(book);
      }
    }

    Future<void> handleShare() async {
      await shareFile(
        title: '${book.title}.${book.filePath.split('.').last}',
        filePath: book.fileFullPath,
      );
    }

    String formatSize(int bytes) {
      if (bytes <= 0) return '0 B';
      const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    Future<void> handleReplace(BuildContext context) async {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null) return;
      PlatformFile newFile = result.files.first;
      String extension =
          p.extension(newFile.name).replaceAll('.', '').toLowerCase();
      if (!allowBookExtensions.contains(extension)) {
        if (context.mounted) {
          AnxToast.show(
              L10n.of(context).bookBottomSheetUnsupportedFileFormat(extension));
        }
        return;
      }

      File newFileObj = File(newFile.path!);

      if (!context.mounted) return;

      int newSize = await newFileObj.length();
      int oldSize = 0;
      if (await File(book.fileFullPath).exists()) {
        oldSize = await File(book.fileFullPath).length();
      }

      bool? confirm = await SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).commonAttention),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(context)
                  .bookBottomSheetOriginalFileSize(formatSize(oldSize))),
              Text(L10n.of(context)
                  .bookBottomSheetNewFileSize(formatSize(newSize))),
              const SizedBox(height: 10),
              Text(
                L10n.of(context).bookBottomSheetReplaceWarning,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: false),
              child: Text(L10n.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: true),
              child: Text(
                L10n.of(context).commonConfirm,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      try {
        File fileToProcess = newFileObj;

        // Convert TXT to EPUB if needed
        if (extension == 'txt') {
          fileToProcess = await convertFromTxt(newFileObj);
          extension = 'epub';
        }

        // Generate new file name and path
        String oldFileName = p.basename(book.filePath);
        String nameWithoutExtension = p.basenameWithoutExtension(oldFileName);
        String newFileName = '$nameWithoutExtension$extension';
        String newRelativePath = 'file/$newFileName';
        String newDestPath = getBasePath(newRelativePath);

        // Copy new file
        await fileToProcess.copy(newDestPath);

        // Calculate MD5
        String? newMd5 = await MD5Service.calculateFileMd5(newDestPath);

        // Update DB
        await bookDao.updateBook(book.copyWith(
          filePath: newRelativePath,
          md5: newMd5,
          updateTime: DateTime.now(),
        ));

        // Delete old file if path is different
        if (book.fileFullPath != newDestPath) {
          final oldFile = File(book.fileFullPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        }

        // Clean up temporary file if TXT conversion happened
        if (fileToProcess != newFileObj) {
          if (await fileToProcess.exists()) {
            await fileToProcess.delete();
          }
        }

        ref.read(bookListProvider.notifier).refresh();
        if (context.mounted) Navigator.pop(context);

        if (Prefs().webdavStatus) {
          ref.read(syncProvider.notifier).syncData(SyncDirection.upload, ref);
        }
      } catch (e) {
        if (context.mounted) {
          AnxToast.show(
              L10n.of(context).bookBottomSheetReplaceFailed(e.toString()));
        }
      }
    }

    Future<void> handleStatusChange(ReadingStatus newStatus) async {
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
      if (context.mounted) {
        Navigator.pop(context);
      }
    }

    final moreActions = [
      {
        "icon": EvaIcons.refresh,
        "text": L10n.of(context).bookBottomSheetReplaceFile,
        "onTap": () => handleReplace(context)
      },
      {
        "icon": EvaIcons.cloud_upload,
        "text": L10n.of(context).bookSyncStatusReleaseSpace,
        "onTap": () => handleUpload(context)
      },
    ];

    Widget buildStatusPills() {
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

      return Row(
        children: items.map((item) {
          final isSelected = book.status == item.$1;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Material(
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withAlpha(120),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    handleStatusChange(item.$1);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.$3,
                          size: 15,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            buildStatusPills(),
            const SizedBox(height: 10),
            Row(
              children: [
                BookCover(book: book, width: 42, height: 60),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        book.author.isNotEmpty ? book.author : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withAlpha(180),
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(EvaIcons.info_outline, size: 20),
                  tooltip: L10n.of(context).notesPageDetail,
                  onPressed: () => handleDetail(context),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  icon: const Icon(EvaIcons.share_outline, size: 20),
                  tooltip: L10n.of(context).shareFile,
                  onPressed: handleShare,
                ),
                const SizedBox(width: 4),
                DeleteConfirm(
                  delete: () => handleDelete(context),
                  deleteIcon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withAlpha(120),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      EvaIcons.trash,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  confirmIcon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      EvaIcons.checkmark_circle_2,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton(
                  itemBuilder: (context) => moreActions.map((action) {
                    return PopupMenuItem(
                      onTap: () {
                        (action["onTap"] as Function())();
                      },
                      child: Row(
                        children: [
                          Icon(action["icon"] as IconData, size: 20),
                          const SizedBox(width: 10),
                          Text(action["text"] as String),
                        ],
                      ),
                    );
                  }).toList(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                          .withAlpha(120),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(EvaIcons.more_vertical, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
