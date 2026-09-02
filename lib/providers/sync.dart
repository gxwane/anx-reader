import 'dart:async';
import 'dart:io' as io;
import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/models/sync/book_progress_payload.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_local_change_detector.dart';
import 'package:anx_reader/service/sync/database_merger.dart';
import 'package:anx_reader/service/sync/progress_sync_manager.dart';
import 'package:anx_reader/service/database_sync_manager.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync.g.dart';

@Riverpod(keepAlive: true)
class Sync extends _$Sync {
  static final Sync _instance = Sync._internal();
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static Timer? _debounceTimer;

  factory Sync() {
    return _instance;
  }

  Sync._internal();

  /// Starts listening for network recovery to automatically drain pending sync queue.
  static void initConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(seconds: 5), () {
          Sync().processPendingSyncQueue();
        });
      }
    });
  }

  @override
  SyncStateModel build() {
    return const SyncStateModel(
      direction: SyncDirection.both,
      isSyncing: false,
      total: 0,
      count: 0,
      fileName: '',
    );
  }

  void changeState(SyncStateModel s) {
    state = s;
  }

  SyncClientBase? get _syncClient {
    if (SyncClientFactory.currentClient == null) {
      SyncClientFactory.initializeCurrentClient();
    }
    return SyncClientFactory.currentClient;
  }

  Future<void> init() async {
    final client = _syncClient;
    if (client == null) {
      AnxLog.severe('No sync client configured');
      return;
    }

    AnxLog.info('${client.protocolName}: init');
  }

  Future<void> _createAnxDir() async {
    final client = _syncClient;
    if (client == null) return;

    if (!await client.isExist(AppIdentity.syncPath('data/file'))) {
      await client.mkdirAll(AppIdentity.syncPath('data/file'));
      await client.mkdirAll(AppIdentity.syncPath('data/cover'));
    }
  }

  Future<bool> shouldSync() async {
    if (!Prefs().webdavStatus) {
      return false;
    }

    if (Prefs().onlySyncWhenWifi &&
        !(await Connectivity().checkConnectivity())
            .contains(ConnectivityResult.wifi)) {
      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavOnlyWifi);
      }
      return false;
    }

    return true;
  }

  Future<SyncDirection?> determineSyncDirection(
      SyncDirection requestedDirection) async {
    final client = _syncClient;
    if (client == null) return null;

    String remoteDbFileName = 'database$currentDbVersion.db';

    // Check for version mismatch
    List<RemoteFile> remoteFiles = [];
    try {
      remoteFiles = await client.safeReadDir(AppIdentity.syncPath());
    } catch (e) {
      await _createAnxDir();
      remoteFiles = await client.safeReadDir(AppIdentity.syncPath());
    }

    for (var file in remoteFiles) {
      if (file.name != null &&
          file.name!.startsWith('database') &&
          file.name!.endsWith('.db')) {
        String versionStr =
            file.name!.replaceAll('database', '').replaceAll('.db', '');
        int version = int.tryParse(versionStr) ?? 0;
        if (version > currentDbVersion) {
          await _showDatabaseVersionMismatchDialog(version);
          return null;
        }
      }
    }

    RemoteFile? remoteDb =
        await client.readProps(AppIdentity.syncPath(remoteDbFileName));
    final databasePath = await getAnxDataBasesPath();
    final localDbPath = join(databasePath, 'app_database.db');

    // Use getLatestModTime to include WAL file modification time
    final localDbTime = DBHelper.getLatestModTime(localDbPath);
    AnxLog.info('localDbTime: $localDbTime, remoteDbTime: ${remoteDb?.mTime}');

    if (remoteDb == null) {
      return SyncDirection.upload;
    }

    return requestedDirection;
  }

  Future<void> _showDatabaseVersionMismatchDialog(int remoteVersion) async {
    await SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).webdavSyncAborted),
        content: Text(
            L10n.of(context).syncMismatchTip(currentDbVersion, remoteVersion)),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> syncData(
    SyncDirection direction,
    WidgetRef? ref, {
    SyncTrigger trigger = SyncTrigger.auto,
  }) async {
    final client = _syncClient;
    if (client == null) {
      AnxLog.info('No sync client configured');
      return;
    }

    if (trigger == SyncTrigger.auto && !Prefs().autoSync) {
      return;
    }

    if (!(await shouldSync())) {
      return;
    }

    // Check if already syncing - MOVED BEFORE determineSyncDirection
    if (state.isSyncing) {
      AnxLog.info('Sync already in progress, skipping');
      return;
    }

    // Test ping and initialize
    try {
      await client.ping();
      await _createAnxDir();
    } catch (e) {
      AnxLog.severe('Sync connection failed, ping failed2\n${e.toString()}');
      return;
    }

    AnxLog.info('Sync ping success');

    // Determine sync direction
    SyncDirection? finalDirection = await determineSyncDirection(direction);
    if (finalDirection == null) {
      return; // User cancelled or no sync needed
    }

    changeState(state.copyWith(isSyncing: true));

    if (Prefs().syncCompletedToast) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncing);
    }

    try {
      await syncDatabase(finalDirection);

      if (await isCurrentEmpty()) {
        await _showSyncAbortedDialog();
        changeState(state.copyWith(isSyncing: false));
        return;
      }

      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncingFiles);
      }

      await syncFiles();

      imageCache.clear();
      imageCache.clearLiveImages();

      try {
        this.ref.read(bookListProvider.notifier).refresh();
        this.ref.read(groupDaoProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh book list: $e');
      }

      // Backup cleanup is now handled by DatabaseSyncManager

      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncComplete);
      }
    } catch (e, s) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        AnxToast.show('Sync connection failed, check your network');
        AnxLog.severe('Sync connection failed, connection error\n$e, $s');
      } else {
        AnxToast.show('Sync failed\n$e');
        AnxLog.severe('Sync failed\n$e, $s');
      }
    } finally {
      changeState(state.copyWith(isSyncing: false));
      // _deleteBackUpDb();
    }
  }

  Future<void> syncFiles() async {
    final client = _syncClient;
    if (client == null) return;

    AnxLog.info('Sync: syncFiles');
    List<String> currentBooks = await bookDao.getCurrentBooks();
    List<String> currentCover = await bookDao.getCurrentCover();

    List<String> remoteBooksName = [];
    List<String> remoteCoversName = [];

    List<RemoteFile> remoteBooks =
        await client.safeReadDir(AppIdentity.syncPath('data/file'));
    remoteBooksName = List.generate(
        remoteBooks.length, (index) => 'file/${remoteBooks[index].name!}');

    List<RemoteFile> remoteCovers =
        await client.safeReadDir(AppIdentity.syncPath('data/cover'));
    remoteCoversName = List.generate(
        remoteCovers.length, (index) => 'cover/${remoteCovers[index].name!}');

    List<String> totalCurrentFiles = [...currentCover, ...currentBooks];
    List<String> totalRemoteFiles = [...remoteBooksName, ...remoteCoversName];

    List<String> localBooks =
        io.Directory(getBasePath('file')).listSync().map((e) {
      return 'file/${basename(e.path)}';
    }).toList();
    List<String> localCovers =
        io.Directory(getBasePath('cover')).listSync().map((e) {
      return 'cover/${basename(e.path)}';
    }).toList();
    List<String> totalLocalFiles = [...localBooks, ...localCovers];

    // Abort if totalCurrentFiles is empty
    if (totalCurrentFiles.isEmpty) {
      await _showSyncAbortedDialog();
      return;
    }

    // Sync cover files
    for (var file in currentCover) {
      if (!remoteCoversName.contains(file) && localCovers.contains(file)) {
        await uploadFile(getBasePath(file), AppIdentity.syncPath('data/$file'));
      }
      if (!io.File(getBasePath(file)).existsSync() &&
          remoteCoversName.contains(file)) {
        await downloadFile(
            AppIdentity.syncPath('data/$file'), getBasePath(file));
      }
    }

    // Sync book files
    for (var file in currentBooks) {
      if (!remoteBooksName.contains(file) && localBooks.contains(file)) {
        await uploadFile(getBasePath(file), AppIdentity.syncPath('data/$file'));
      }
    }

    // Remove remote files not in database
    for (var file in totalRemoteFiles) {
      if (!totalCurrentFiles.contains(file)) {
        await client.remove(AppIdentity.syncPath('data/$file'));
      }
    }

    // Remove local files not in database
    for (var file in totalLocalFiles) {
      if (!totalCurrentFiles.contains(file)) {
        await io.File(getBasePath(file)).delete();
      }
    }
    ref.read(syncStatusProvider.notifier).refresh();
  }

  /// Upload a VACUUM INTO snapshot of the local DB to the remote server.
  /// Captures [localDbPath] mtime BEFORE snapshot creation so that any
  /// writes that arrive during the upload are not mistakenly marked as synced.
  Future<DateTime> _uploadDatabaseSnapshot(
    String remoteDbFileName,
    String localDbPath,
  ) async {
    final preUploadLocalTime = DBHelper.getLatestModTime(localDbPath);
    final snapshotPath = await DBHelper.prepareUploadSnapshot();
    try {
      await uploadFile(snapshotPath, AppIdentity.syncPath(remoteDbFileName));
    } finally {
      final snapshotFile = io.File(snapshotPath);
      if (snapshotFile.existsSync()) await snapshotFile.delete();
    }
    return preUploadLocalTime;
  }

  /// Download and validate the remote DB; returns false if the download failed
  /// or the remote DB does not exist (also shows the appropriate dialog).
  Future<bool> _safeDownloadDatabase(
    SyncClientBase client,
    String remoteDbFileName,
    RemoteFile? remoteDb,
  ) async {
    if (remoteDb == null) {
      await _showSyncAbortedDialog();
      return false;
    }
    final result = await DatabaseSyncManager.safeDownloadDatabase(
      client: client,
      remoteDbFileName: remoteDbFileName,
      onProgress: (received, total) {
        changeState(state.copyWith(
          direction: SyncDirection.download,
          fileName: remoteDbFileName,
          isSyncing: received < total,
          count: received,
          total: total,
        ));
      },
    );
    if (!result.isSuccess) {
      await DatabaseSyncManager.showSyncErrorDialog(result);
      AnxLog.severe('Database sync failed: ${result.message}');
      return false;
    }
    return true;
  }

  /// Persist last-sync timestamps after a successful database sync operation.
  Future<void> _updateSyncTimestamps(
    SyncClientBase client,
    String remoteDbFileName,
    DateTime localTimeToRecord,
  ) async {
    final newRemoteDb =
        await client.readProps(AppIdentity.syncPath(remoteDbFileName));
    if (newRemoteDb != null) {
      Prefs().lastUploadBookDate = newRemoteDb.mTime;
      Prefs().lastSyncedLocalDbTime = localTimeToRecord;
    }
  }

  Future<void> syncDatabase(SyncDirection direction) async {
    final client = _syncClient;
    if (client == null) return;

    final remoteDbFileName = 'database$currentDbVersion.db';
    final remoteDb =
        await client.readProps(AppIdentity.syncPath(remoteDbFileName));
    final databasePath = await getAnxDataBasesPath();
    final localDbPath = join(databasePath, 'app_database.db');

    // localTimeToRecord defaults to current mtime (download/skip paths).
    // Upload paths override it via _uploadDatabaseSnapshot return value.
    DateTime localTimeToRecord = DBHelper.getLatestModTime(localDbPath);

    try {
      switch (direction) {
        case SyncDirection.upload:
          localTimeToRecord =
              await _uploadDatabaseSnapshot(remoteDbFileName, localDbPath);
          break;

        case SyncDirection.download:
          final ok =
              await _safeDownloadDatabase(client, remoteDbFileName, remoteDb);
          if (!ok) return;
          localTimeToRecord = DBHelper.getLatestModTime(localDbPath);
          break;

        case SyncDirection.both:
          final remoteChanged = Prefs().lastUploadBookDate == null ||
              (remoteDb?.mTime != null &&
                  Prefs()
                          .lastUploadBookDate!
                          .difference(remoteDb!.mTime!)
                          .inSeconds
                          .abs() >
                      5);

          final localChanged =
              SyncLocalChangeDetector.hasLocalChangedSinceLastSync(
            currentLocalTime: DBHelper.getLatestModTime(localDbPath),
            lastSyncedLocalDbTime: Prefs().lastSyncedLocalDbTime,
          );

          if (remoteDb != null && remoteChanged) {
            AnxLog.info(
                'Sync(both): Remote DB changed, performing non-destructive merge');
            final merged = await DatabaseMerger.mergeFromRemote(
              client: client,
              remoteDbFileName: remoteDbFileName,
            );
            if (merged) {
              localTimeToRecord =
                  await _uploadDatabaseSnapshot(remoteDbFileName, localDbPath);
              try {
                ref.read(bookListProvider.notifier).refresh();
              } catch (_) {}
            }
          } else if (remoteDb == null || localChanged) {
            localTimeToRecord =
                await _uploadDatabaseSnapshot(remoteDbFileName, localDbPath);
          } else {
            AnxLog.info(
                'Sync(both): Neither local nor remote changed, skipping DB sync');
          }
          break;
      }

      await _updateSyncTimestamps(client, remoteDbFileName, localTimeToRecord);
    } catch (e) {
      AnxLog.severe('Failed to sync database\n$e');
      rethrow;
    }
  }

  ProgressSyncManager? get progressSyncManager =>
      _syncClient != null ? ProgressSyncManager(_syncClient!) : null;

  /// Background dispatch for single-book progress micro-sync
  Future<void> syncBookProgress(Book book) async {
    final mgr = progressSyncManager;
    if (mgr == null) return;
    await mgr.uploadBookProgress(book);
  }

  /// Fetches remote progress for a book without blocking UI
  Future<BookProgressPayload?> fetchBookProgress(String fileMd5) async {
    final mgr = progressSyncManager;
    if (mgr == null) return null;
    return await mgr.fetchRemoteProgress(fileMd5);
  }

  /// Background dispatch for single-book notes micro-sync
  Future<void> syncBookNotes(Book book) async {
    final mgr = progressSyncManager;
    if (mgr == null) return;
    await mgr.uploadBookNotes(book);
  }

  /// Merges remote notes into local book
  Future<void> mergeBookNotes(Book book) async {
    final mgr = progressSyncManager;
    if (mgr == null) return;
    await mgr.mergeRemoteNotes(book);
  }

  /// Drains any offline pending sync books in the background.
  Future<void> processPendingSyncQueue() async {
    if (!Prefs().webdavStatus) return;
    final mgr = progressSyncManager;
    if (mgr == null) return;
    await mgr.drainPendingQueue(BookDao());
  }

  Future<void> uploadFile(
    String localPath,
    String remotePath, [
    bool replace = true,
  ]) async {
    changeState(state.copyWith(
      direction: SyncDirection.upload,
      fileName: localPath.split('/').last,
    ));

    final client = _syncClient;
    if (client != null) {
      ref.read(syncStatusProvider.notifier).addUploading(remotePath);
      await client.uploadFile(
        localPath,
        remotePath,
        replace: replace,
        onProgress: (sent, total) {
          changeState(state.copyWith(
            isSyncing: true,
            count: sent,
            total: total,
          ));
        },
      );
      ref.read(syncStatusProvider.notifier).removeUploading(remotePath);
    }

    changeState(state.copyWith(isSyncing: false));
  }

  Future<void> downloadFile(String remotePath, String localPath) async {
    changeState(state.copyWith(
      direction: SyncDirection.download,
      fileName: remotePath.split('/').last,
    ));

    final client = _syncClient;
    if (client != null) {
      ref.read(syncStatusProvider.notifier).addDownloading(remotePath);
      await client.downloadFile(
        remotePath,
        localPath,
        onProgress: (received, total) {
          changeState(state.copyWith(
            isSyncing: true,
            count: received,
            total: total,
          ));
        },
      );
      ref.read(syncStatusProvider.notifier).removeDownloading(remotePath);
    }

    changeState(state.copyWith(isSyncing: false));
  }

  Future<List<String>> listRemoteBookFiles() async {
    final client = _syncClient;
    if (client == null) return [];

    final remoteFiles =
        await client.safeReadDir(AppIdentity.syncPath('data/file'));
    return remoteFiles.map((e) => e.name!).toList();
  }

  Future<void> downloadBook(Book book) async {
    final syncStatus = await ref.read(syncStatusProvider.future);

    if (!syncStatus.remoteOnly.contains(book.id)) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!)
          .bookSyncStatusBookNotFoundRemote);
      return;
    }

    try {
      await _downloadBook(book);
    } catch (e) {
      // Error handling is done in _downloadBook
    }
  }

  Future<void> releaseBook(Book book) async {
    final syncStatus = await ref.read(syncStatusProvider.future);

    Future<void> deleteLocalBook() async {
      await io.File(getBasePath(book.filePath)).delete();
    }

    Future<void> uploadBook() async {
      try {
        final remotePath = AppIdentity.syncPath('data/${book.filePath}');
        final localPath = getBasePath(book.filePath);
        await uploadFile(localPath, remotePath);
      } catch (e) {
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).bookSyncStatusUploadFailed);
        AnxLog.severe('Failed to upload book\n$e');
        rethrow;
      }
    }

    if (syncStatus.remoteOnly.contains(book.id)) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).bookSyncStatusSpaceReleased);
      return;
    } else if (syncStatus.both.contains(book.id)) {
      await deleteLocalBook();
      ref.read(syncStatusProvider.notifier).refresh();
    } else {
      try {
        await uploadBook();
        await deleteLocalBook();
      } catch (e) {
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).bookSyncStatusUploadFailed);
      }
    }
  }

  Future<void> downloadMultipleBooks(List<int> bookIds) async {
    AnxLog.info(
        'WebDAV: Starting download for ${bookIds.length} remote books.');
    int successCount = 0;
    int failCount = 0;

    try {
      final client = _syncClient;
      if (client != null) {
        await client.ping();
      } else {
        throw Exception('No sync client configured');
      }
    } catch (e) {
      AnxLog.severe(
          'WebDAV connection failed before batch download, ping failed\n${e.toString()}');
      return;
    }

    for (final bookId in bookIds) {
      try {
        final book = await bookDao.selectBookById(bookId);
        AnxLog.info('WebDAV: Downloading book ID $bookId: ${book.title}');
        await _downloadBook(book);
        successCount++;
      } catch (e) {
        AnxLog.severe('WebDAV: Failed to download book ID $bookId: $e');
        failCount++;
      }
    }

    AnxLog.info(L10n.of(navigatorKey.currentContext!)
        .webdavBatchDownloadFinishedReport(successCount, failCount));
    AnxToast.show(L10n.of(navigatorKey.currentContext!)
        .webdavBatchDownloadFinishedReport(successCount, failCount));
  }

  Future<void> _downloadBook(Book book) async {
    try {
      AnxToast.show(L10n.of(navigatorKey.currentContext!)
          .bookSyncStatusDownloadingBook(book.filePath));
      final remotePath = AppIdentity.syncPath('data/${book.filePath}');
      final localPath = getBasePath(book.filePath);
      await downloadFile(remotePath, localPath);
    } catch (e) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).bookSyncStatusDownloadFailed);
      AnxLog.severe('Failed to download book\n$e');
      rethrow;
    }
  }

  Future<bool> isCurrentEmpty() async {
    List<String> currentBooks = await bookDao.getCurrentBooks();
    List<String> currentCover = await bookDao.getCurrentCover();
    List<String> totalCurrentFiles = [...currentCover, ...currentBooks];
    return totalCurrentFiles.isEmpty;
  }

  /// Get available database backup list
  Future<List<String>> getAvailableBackups() async {
    return await DatabaseSyncManager.getAvailableBackups();
  }

  /// Show database backup management dialog
  Future<void> showBackupManagementDialog() async {
    try {
      final backups = await getAvailableBackups();

      await SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).databaseBackupManagement),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context).availableBackups),
                const SizedBox(height: 12),
                if (backups.isEmpty)
                  Text(
                    L10n.of(context).noBackupsAvailable,
                    style: const TextStyle(color: Colors.grey),
                  )
                else
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: backups.length,
                      itemBuilder: (context, index) {
                        final backup = backups[index];
                        final fileName = backup.split('/').last;
                        final timestamp = fileName
                            .replaceAll('backup_database_', '')
                            .replaceAll('.db', '');

                        return ListTile(
                          title: Text('Backup ${index + 1}'),
                          subtitle: Text(timestamp),
                          trailing: ElevatedButton(
                            onPressed: () async {
                              // Navigator.of(context).pop();
                              await _restoreFromBackup(backup);
                            },
                            child: Text(L10n.of(context).restore),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L10n.of(context).commonCancel),
            ),
          ],
        ),
      );
    } catch (e) {
      AnxLog.severe('Failed to show backup management dialog: $e');
      AnxToast.show('Failed to get backup list: $e');
    }
  }

  /// Restore database from specified backup
  Future<void> _restoreFromBackup(String backupPath) async {
    try {
      final databasePath = await getAnxDataBasesPath();
      final localDbPath = join(databasePath, 'app_database.db');

      // Confirmation dialog
      final confirmed = await SmartDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).confirmRestore),
          content: Text(L10n.of(context).restoreWarning),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: false),
              child: Text(L10n.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => SmartDialog.dismiss(result: true),
              child: Text(L10n.of(context).commonConfirm),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Execute restore
      await DBHelper.close();
      await io.File(backupPath).copy(localDbPath);
      await DBHelper().initDB();

      // Refresh related providers
      try {
        ref.read(bookListProvider.notifier).refresh();
        ref.read(groupDaoProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh providers after restore: $e');
      }

      AnxToast.show(L10n.of(navigatorKey.currentContext!).restoreSuccess);
      AnxLog.info('Database restored from backup: $backupPath');
    } catch (e) {
      AnxLog.severe('Failed to restore from backup: $e');
      AnxToast.show('Restore failed: $e');
    }
  }

  Future<void> _showSyncAbortedDialog() async {
    await SmartDialog.show(
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).webdavSyncAborted),
        content: Text(L10n.of(context).webdavSyncAbortedContent),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }
}
