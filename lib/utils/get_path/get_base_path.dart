import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String documentPath = '';

/// Check if a path is accessible (can read and write)
Future<bool> _isPathAccessible(String path) async {
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) return false;

    // Try to create and delete a test file to verify write permission
    final testFile = File('$path${Platform.pathSeparator}.anx_permission_test');
    await testFile.writeAsString('test');
    await testFile.delete();
    return true;
  } catch (e) {
    AnxLog.warning('Path not accessible: $path, error: $e');
    return false;
  }
}

Future<String> getAnxDocumentsPath() async {
  // Windows only: Check for custom storage path first
  if (AnxPlatform.isWindows) {
    final customPath = Prefs().customStoragePath;
    if (customPath != null) {
      // Verify the path is still accessible (permission may have been revoked)
      if (await _isPathAccessible(customPath)) {
        return customPath;
      } else {
        // Permission lost, clear the custom path
        AnxLog.warning(
            'Custom storage path no longer accessible, resetting to default');
        Prefs().customStoragePath = null;
      }
    }
  }

  final directory = await getApplicationDocumentsDirectory();
  switch (AnxPlatform.type) {
    case AnxPlatformEnum.android:
    case AnxPlatformEnum.ohos:
      return directory.path;
    case AnxPlatformEnum.windows:
      return (await getApplicationSupportDirectory()).path;
    case AnxPlatformEnum.macos:
      return (await getApplicationSupportDirectory()).path;
    case AnxPlatformEnum.ios:
      return (await getApplicationSupportDirectory()).path;
    case AnxPlatformEnum.linux:
      return (await getApplicationSupportDirectory()).path;
  }
}

Future<Directory> getAnxDocumentDir() async {
  return Directory(await getAnxDocumentsPath());
}

void initBasePath() async {
  Directory appDocDir = await getAnxDocumentDir();
  documentPath = appDocDir.path;
  debugPrint('documentPath: $documentPath');
  final fileDir = getFileDir();
  final coverDir = getCoverDir();
  final fontDir = getFontDir();
  final bgimgDir = getBgimgDir();
  if (!fileDir.existsSync()) {
    fileDir.createSync(recursive: true);
  }
  if (!coverDir.existsSync()) {
    coverDir.createSync(recursive: true);
  }
  if (!fontDir.existsSync()) {
    fontDir.createSync(recursive: true);
  }
  if (!bgimgDir.existsSync()) {
    bgimgDir.createSync(recursive: true);
  }
}

String _resolveBasePath(String? path) {
  if (path != null && path.isNotEmpty) {
    return path;
  }
  if (documentPath.isNotEmpty) {
    return documentPath;
  }
  return Directory.systemTemp.path;
}

String getBasePath(String path) {
  // the path that in database using "/"
  final normalized = path.replaceAll("/", Platform.pathSeparator);
  final base = _resolveBasePath(null);
  return '$base${Platform.pathSeparator}$normalized';
}

Directory getFontDir({String? path}) {
  final base = _resolveBasePath(path);
  return Directory('$base${Platform.pathSeparator}font');
}

Directory getCoverDir({String? path}) {
  final base = _resolveBasePath(path);
  return Directory('$base${Platform.pathSeparator}cover');
}

Directory getFileDir({String? path}) {
  final base = _resolveBasePath(path);
  return Directory('$base${Platform.pathSeparator}file');
}

Directory getBgimgDir({String? path}) {
  final base = _resolveBasePath(path);
  return Directory('$base${Platform.pathSeparator}bgimg');
}
