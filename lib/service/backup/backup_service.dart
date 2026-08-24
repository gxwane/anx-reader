import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/preview_import_policy.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

const String backupPrefsFileName = 'anx_shared_prefs.json';

class BackupExportResult {
  const BackupExportResult({
    required this.zipPath,
    required this.fileName,
  });

  final String zipPath;
  final String fileName;
}

class BackupService {
  Future<BackupExportResult> createExport() async {
    final stopwatch = Stopwatch()..start();
    final prefsBackupFile = await _createPrefsBackupFile();
    AnxLog.info(
      'exportData: prefs backup created in ${stopwatch.elapsedMilliseconds}ms',
    );

    try {
      final now = DateTime.now();
      final tempDir = await getAnxTempDir();
      final zipPath = path.join(
        tempDir.path,
        'AnxReader-Backup-${now.year}-${now.month}-${now.day}-${now.millisecondsSinceEpoch}.zip',
      );
      final docPath = await getAnxDocumentsPath();
      final dbDir = await getAnxDataBasesDir();
      final token = RootIsolateToken.instance!;
      final createdZipPath = await compute(_createZipFile, {
        'token': token,
        'zipPath': zipPath,
        'fileDirPath': getFileDir(path: docPath).path,
        'coverDirPath': getCoverDir(path: docPath).path,
        'fontDirPath': getFontDir(path: docPath).path,
        'bgimgDirPath': getBgimgDir(path: docPath).path,
        'dbDirPath': dbDir.path,
        'isOhos': AnxPlatform.isOhos,
        'prefsBackupFilePath': prefsBackupFile.path,
      });
      return BackupExportResult(
        zipPath: createdZipPath,
        fileName: 'AnxReader-Backup-${now.year}-${now.month}-${now.day}-v3.zip',
      );
    } finally {
      if (await prefsBackupFile.exists()) {
        await prefsBackupFile.delete();
      }
    }
  }

  Future<void> importFromZip(String zipFilePath) async {
    final stopwatch = Stopwatch()..start();
    final tempDir = await getAnxTempDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extractPath = path.join(tempDir.path, 'anx_reader_import_$timestamp');
    final rollbackPath =
        path.join(tempDir.path, 'anx_reader_import_rollback_$timestamp');

    try {
      await Directory(extractPath).create(recursive: true);
      await Directory(rollbackPath).create(recursive: true);

      await compute(_extractZipFile, {
        'zipFilePath': zipFilePath,
        'destinationPath': extractPath,
      });
      AnxLog.info(
        'importData: unzip completed in ${stopwatch.elapsedMilliseconds}ms',
      );

      await _validateExtractedBackup(extractPath);

      final docPath = await getAnxDocumentsPath();
      final targets = <_DirectoryRestoreTarget>[
        _DirectoryRestoreTarget(
          name: 'file',
          source: Directory(path.join(extractPath, 'file')),
          destination: getFileDir(path: docPath),
        ),
        _DirectoryRestoreTarget(
          name: 'cover',
          source: Directory(path.join(extractPath, 'cover')),
          destination: getCoverDir(path: docPath),
        ),
        _DirectoryRestoreTarget(
          name: 'font',
          source: Directory(path.join(extractPath, 'font')),
          destination: getFontDir(path: docPath),
        ),
        _DirectoryRestoreTarget(
          name: 'bgimg',
          source: Directory(path.join(extractPath, 'bgimg')),
          destination: getBgimgDir(path: docPath),
        ),
        _DirectoryRestoreTarget(
          name: 'databases',
          source: Directory(path.join(extractPath, 'databases')),
          destination: await getAnxDataBasesDir(),
        ),
      ];

      await _backupExistingTargets(targets, rollbackPath);

      try {
        await DBHelper.close();
        await compute(_restoreDirectories, {
          'targets': targets
              .map((target) => {
                    'name': target.name,
                    'source': target.source.path,
                    'destination': target.destination.path,
                  })
              .toList(growable: false),
        });
        await _restorePrefsFromBackup(extractPath);
        await Prefs().clearSyncConfiguration();
        SyncClientFactory.resetCurrentClient();
        await DBHelper().initDB();
      } catch (error, stackTrace) {
        AnxLog.severe('importData: restore failed, rolling back: $error', error,
            stackTrace);
        await DBHelper.close();
        await compute(_rollbackDirectories, {
          'targets': targets
              .map((target) => {
                    'name': target.name,
                    'destination': target.destination.path,
                    'backup': path.join(rollbackPath, target.name),
                  })
              .toList(growable: false),
        });
        await DBHelper().initDB();
        rethrow;
      }

      AnxLog.info(
        'importData: import completed in ${stopwatch.elapsedMilliseconds}ms',
      );
    } finally {
      await _deleteIfExists(Directory(extractPath));
      await _deleteIfExists(Directory(rollbackPath));
    }
  }

  Future<File> _createPrefsBackupFile() async {
    final tempDir = await getAnxTempDir();
    final backupFile = File(path.join(tempDir.path, backupPrefsFileName));
    final prefsMap = await Prefs().buildPrefsBackupMap();
    await backupFile.writeAsString(jsonEncode(prefsMap));
    return backupFile;
  }

  Future<void> _validateExtractedBackup(String extractPath) async {
    final dbFile = File(path.join(extractPath, 'databases', 'app_database.db'));
    if (!await dbFile.exists()) {
      throw StateError('Backup is missing databases/app_database.db');
    }
  }

  Future<void> _backupExistingTargets(
    List<_DirectoryRestoreTarget> targets,
    String rollbackPath,
  ) async {
    await compute(_copyExistingTargets, {
      'targets': targets
          .map((target) => {
                'name': target.name,
                'destination': target.destination.path,
                'backup': path.join(rollbackPath, target.name),
              })
          .toList(growable: false),
    });
  }

  Future<bool> _restorePrefsFromBackup(String extractPath) async {
    final backupFile = File(path.join(extractPath, backupPrefsFileName));
    if (!await backupFile.exists()) {
      return false;
    }
    try {
      final decoded = jsonDecode(await backupFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        await Prefs().applyPrefsBackupMap(
          decoded,
          additionalSkipKeys: PreviewImportPolicy.upstreamBackupSkipKeys,
        );
        return true;
      }
      AnxLog.info('importData: prefs backup has unexpected format');
    } catch (e) {
      AnxLog.info('importData: failed to restore prefs backup: $e');
    }
    return false;
  }

  Future<void> _deleteIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _DirectoryRestoreTarget {
  const _DirectoryRestoreTarget({
    required this.name,
    required this.source,
    required this.destination,
  });

  final String name;
  final Directory source;
  final Directory destination;
}

Future<String> _createZipFile(Map<String, dynamic> params) async {
  final token = params['token'] as RootIsolateToken;
  final zipPath = params['zipPath'] as String;
  final fileDirPath = params['fileDirPath'] as String;
  final coverDirPath = params['coverDirPath'] as String;
  final fontDirPath = params['fontDirPath'] as String;
  final bgimgDirPath = params['bgimgDirPath'] as String;
  final dbDirPath = params['dbDirPath'] as String;
  final isOhos = params['isOhos'] as bool;
  final prefsBackupFilePath = params['prefsBackupFilePath'] as String;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final stopwatch = Stopwatch()..start();
  final prefsBackupFile = File(prefsBackupFilePath);

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  try {
    await _addDirectoryIfExists(encoder, Directory(fileDirPath));
    await _addDirectoryIfExists(encoder, Directory(coverDirPath));
    await _addDirectoryIfExists(encoder, Directory(fontDirPath));
    await _addDirectoryIfExists(encoder, Directory(bgimgDirPath));
    await _addDatabaseBackup(
      encoder,
      dbDirPath: dbDirPath,
      isOhos: isOhos,
    );
    if (await prefsBackupFile.exists()) {
      await encoder.addFile(prefsBackupFile);
    }
  } finally {
    encoder.close();
  }

  AnxLog.info('exportData: zip created in ${stopwatch.elapsedMilliseconds}ms');
  return zipPath;
}

Future<void> _addDirectoryIfExists(
  ZipFileEncoder encoder,
  Directory directory,
) async {
  if (await directory.exists()) {
    await encoder.addDirectory(directory);
  }
}

Future<void> _addDatabaseBackup(
  ZipFileEncoder encoder, {
  required String dbDirPath,
  required bool isOhos,
}) async {
  final dbDir = Directory(dbDirPath);
  if (isOhos) {
    final dbFile = File(path.join(dbDir.path, 'app_database.db'));
    if (await dbFile.exists()) {
      await encoder.addFile(dbFile, 'databases/app_database.db');
    }
    return;
  }
  await _addDirectoryIfExists(encoder, dbDir);
}

Future<void> _extractZipFile(Map<String, String> params) async {
  final zipFilePath = params['zipFilePath']!;
  final destinationPath = params['destinationPath']!;

  final input = InputFileStream(zipFilePath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    extractArchiveToDiskSync(archive, destinationPath);
    archive.clearSync();
  } finally {
    await input.close();
  }
}

Future<void> _copyExistingTargets(Map<String, dynamic> params) async {
  final targets = (params['targets'] as List).cast<Map>();
  for (final target in targets) {
    final destination = Directory(target['destination'] as String);
    final backup = Directory(target['backup'] as String);
    if (destination.existsSync()) {
      _copyDirectorySync(destination, backup);
    }
  }
}

Future<void> _restoreDirectories(Map<String, dynamic> params) async {
  final targets = (params['targets'] as List).cast<Map>();
  for (final target in targets) {
    final source = Directory(target['source'] as String);
    final destination = Directory(target['destination'] as String);
    if (!source.existsSync()) {
      continue;
    }
    if (destination.existsSync()) {
      destination.deleteSync(recursive: true);
    }
    _copyDirectorySync(source, destination);
  }
}

Future<void> _rollbackDirectories(Map<String, dynamic> params) async {
  final targets = (params['targets'] as List).cast<Map>();
  for (final target in targets) {
    final destination = Directory(target['destination'] as String);
    final backup = Directory(target['backup'] as String);
    if (destination.existsSync()) {
      destination.deleteSync(recursive: true);
    }
    if (backup.existsSync()) {
      _copyDirectorySync(backup, destination);
    }
  }
}

void _copyDirectorySync(Directory source, Directory destination) {
  if (!source.existsSync()) {
    return;
  }
  destination.createSync(recursive: true);
  for (final entity in source.listSync(recursive: false)) {
    final newPath = path.join(destination.path, path.basename(entity.path));
    if (entity is File) {
      File(newPath).parent.createSync(recursive: true);
      entity.copySync(newPath);
    } else if (entity is Directory) {
      _copyDirectorySync(entity, Directory(newPath));
    }
  }
}
