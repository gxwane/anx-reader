import 'dart:io';

import 'package:anx_reader/utils/log/common.dart';
import 'package:path_provider/path_provider.dart';

/// Callback for migration progress updates
typedef MigrationProgressCallback = void Function(
    String currentItem, int progress, int total);

/// Returns true if [path] looks like an existing Anx Reader library directory.
/// Detection heuristic: the directory must exist and contain at least one of
/// the canonical Anx sub-directories ('databases', 'file', 'cover', 'font').
bool isAnxLibraryDirectory(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return false;
  const anxSubDirs = {'databases', 'file', 'cover', 'font'};
  return dir
      .listSync(followLinks: false)
      .whereType<Directory>()
      .any((d) => anxSubDirs.contains(d.path.split(Platform.pathSeparator).last));
}

/// Performs data migration from source path to destination path.
/// Used for custom storage location feature on Windows/macOS.
/// Returns true if migration was successful.
Future<bool> performStorageMigration({
  required String sourcePath,
  required String destinationPath,
  MigrationProgressCallback? onProgress,
}) async {
  final dataFolders = ['file', 'cover', 'font', 'bgimg', 'databases'];
  final successfullyMigrated = <String>[];
  const int totalItems = 6; // 5 folders + 1 log file

  try {
    for (int i = 0; i < dataFolders.length; i++) {
      final folder = dataFolders[i];
      onProgress?.call(folder, i + 1, totalItems);

      final sourceDir =
          Directory('$sourcePath${Platform.pathSeparator}$folder');
      final destDir =
          Directory('$destinationPath${Platform.pathSeparator}$folder');

      if (!sourceDir.existsSync()) {
        continue;
      }

      if (!destDir.existsSync()) {
        await destDir.create(recursive: true);
      }

      await _copyDirectory(sourceDir, destDir);
      successfullyMigrated.add(folder);

      AnxLog.info('StorageMigration: Copied $folder successfully');
    }

    // Also copy the log file if it exists
    onProgress?.call('anx_reader.log', 6, totalItems);
    final sourceLogFile =
        File('$sourcePath${Platform.pathSeparator}anx_reader.log');
    if (sourceLogFile.existsSync()) {
      final destLogFile =
          File('$destinationPath${Platform.pathSeparator}anx_reader.log');
      await sourceLogFile.copy(destLogFile.path);
      AnxLog.info('StorageMigration: Copied log file successfully');
    }

    // All copies successful — now delete old data
    AnxLog.info(
        'StorageMigration: All data copied, cleaning up source data...');
    for (final folder in successfullyMigrated) {
      final sourceDir =
          Directory('$sourcePath${Platform.pathSeparator}$folder');
      if (sourceDir.existsSync()) {
        await sourceDir.delete(recursive: true);
        AnxLog.info('StorageMigration: Deleted source $folder');
      }
    }

    if (sourceLogFile.existsSync()) {
      await sourceLogFile.delete();
    }

    AnxLog.info('StorageMigration: Completed successfully');
    return true;
  } catch (e) {
    AnxLog.severe('StorageMigration failed: $e');
    return false;
  }
}

/// Checks if a directory is empty (contains no files or subdirectories)
Future<bool> isDirectoryEmpty(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    return true;
  }
  final contents = await dir.list().toList();
  return contents.isEmpty;
}

/// Gets the default storage path for Windows/macOS
Future<String> getDefaultStoragePath() async {
  return (await getApplicationSupportDirectory()).path;
}

/// Recursively copies a directory.
/// If a file already exists at the destination with the same byte-length as
/// the source, it is skipped (idempotent / resume-safe behaviour).
Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: false)) {
    final lastName = entity.path.split(Platform.pathSeparator).last;
    final newPath = '${destination.path}${Platform.pathSeparator}$lastName';

    if (entity is File) {
      final destFile = File(newPath);
      // Skip if destination already has the same-size file (idempotent)
      if (destFile.existsSync() &&
          destFile.lengthSync() == entity.lengthSync()) {
        continue;
      }
      await entity.copy(newPath);
    } else if (entity is Directory) {
      final newDir = Directory(newPath);
      await newDir.create(recursive: true);
      await _copyDirectory(entity, newDir);
    }
  }
}
