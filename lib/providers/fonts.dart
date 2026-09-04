import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/font_source_model.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'fonts.g.dart';
part 'fonts.freezed.dart';

const String fontBaseUrl = 'https://fonts.anxcye.com/';
const String fontManifestUrl = '${fontBaseUrl}fonts-manifest.json';
const String fontManifestBackupUrl =
    'https://raw.githubusercontent.com/Anxcye/anx-reader-fonts/main/fonts-manifest.json';

String resolveFontFileUrl(String manifestUrl, String filePath) {
  if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
    return filePath;
  }
  return Uri.parse(manifestUrl).resolve(filePath).toString();
}

final activeFontSourceProvider = StateProvider<FontSourceModel>((ref) {
  return Prefs().activeFontSource;
});

final onlineFontsIsCacheProvider = StateProvider<bool>((ref) {
  return false;
});

Future<void> validateFontSource(String manifestUrl) async {
  final uri = Uri.tryParse(manifestUrl.trim());
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw const FormatException('Invalid URL scheme. Must be http or https.');
  }
  final response = await http.get(uri).timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw HttpException('Server returned HTTP ${response.statusCode}');
  }
  final dynamic decoded = jsonDecode(response.body);
  if (decoded is! List) {
    throw const FormatException('Manifest root must be a JSON array');
  }
  if (decoded.isEmpty) {
    throw const FormatException('Manifest contains no fonts');
  }
  RemoteFontModel.fromJson(decoded.first as Map<String, dynamic>);
}

@freezed
abstract class LicenseModel with _$LicenseModel {
  const factory LicenseModel({
    required String name,
    required String url,
  }) = _LicenseModel;

  factory LicenseModel.fromJson(Map<String, dynamic> json) =>
      _$LicenseModelFromJson(json);
}

@freezed
abstract class RemoteFontModel with _$RemoteFontModel {
  const factory RemoteFontModel({
    required String id,
    required String name,
    required List<String> files,
    required int size,
    required String preview,
    required String desc,
    required String official,
    required LicenseModel license,
  }) = _RemoteFontModel;

  factory RemoteFontModel.fromJson(Map<String, dynamic> json) =>
      _$RemoteFontModelFromJson(json);
}

enum DownloadStatus {
  none,
  downloading,
  paused,
  completed,
  failed,
}

@freezed
abstract class FontDownloadState with _$FontDownloadState {
  const factory FontDownloadState({
    required String fontId,
    required String filePath,
    required DownloadStatus status,
    @Default(0.0) double progress,
    String? error,
    CancelToken? cancelToken,
  }) = _FontDownloadState;
}

@Riverpod(keepAlive: true)
class Fonts extends _$Fonts {
  @override
  Future<List<RemoteFontModel>> build() async {
    final activeSource = ref.watch(activeFontSourceProvider);

    // Attempt 1: Load from activeSource.manifestUrl
    try {
      final response = await http
          .get(Uri.parse(activeSource.manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await _saveToCache(activeSource.id, response.body);
        ref.read(onlineFontsIsCacheProvider.notifier).state = false;
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) => RemoteFontModel.fromJson(json)).toList();
      }
    } catch (_) {}

    // Attempt 2: If official source, failover to official backup mirror
    if (activeSource.isOfficial) {
      try {
        final backupResponse = await http
            .get(Uri.parse(fontManifestBackupUrl))
            .timeout(const Duration(seconds: 10));
        if (backupResponse.statusCode == 200) {
          await _saveToCache(activeSource.id, backupResponse.body);
          ref.read(onlineFontsIsCacheProvider.notifier).state = false;
          final List<dynamic> jsonList = jsonDecode(backupResponse.body);
          return jsonList
              .map((json) => RemoteFontModel.fromJson(json))
              .toList();
        }
      } catch (_) {}
    }

    // Attempt 3: Fallback to local isolated cache for this source
    final cached = await _loadFromCache(activeSource.id);
    if (cached != null && cached.isNotEmpty) {
      ref.read(onlineFontsIsCacheProvider.notifier).state = true;
      return cached;
    }

    ref.read(onlineFontsIsCacheProvider.notifier).state = false;
    throw Exception('Failed to load fonts manifest from ${activeSource.name}');
  }

  Future<File> _cacheFile(String sourceId) async {
    final baseDir = getFontDir();
    final safeId = sourceId.replaceAll(RegExp(r'[^\w\-]'), '_');
    return File(p.join(baseDir.path, '.cache', 'fonts_manifest_$safeId.json'));
  }

  Future<void> _saveToCache(String sourceId, String body) async {
    try {
      final file = await _cacheFile(sourceId);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(body);
    } catch (_) {}
  }

  Future<List<RemoteFontModel>?> _loadFromCache(String sourceId) async {
    try {
      final file = await _cacheFile(sourceId);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((json) => RemoteFontModel.fromJson(json)).toList();
      }
    } catch (_) {}
    return null;
  }
}

@Riverpod(keepAlive: true)
class FontDownloads extends _$FontDownloads {
  @override
  Map<String, FontDownloadState> build() {
    return {};
  }

  Future<void> startDownload(RemoteFontModel font) async {
    final fontId = font.id;
    final tempDir = await getAnxTempDir();
    final fontDir = getFontDir();
    final dio = Dio();

    final stagingDir =
        Directory(p.join(tempDir.path, 'font_staging_$fontId'));
    final targetDir =
        Directory(p.join(fontDir.path, 'downloaded', fontId));

    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final totalBytes = font.size > 0 ? font.size : 1;
    int previousFilesBytes = 0;
    final cancelToken = CancelToken();

    state = {
      ...state,
      fontId: FontDownloadState(
        fontId: fontId,
        filePath: font.files.firstOrNull ?? '',
        status: DownloadStatus.downloading,
        progress: 0.0,
        cancelToken: cancelToken,
      ),
    };

    final activeSource = ref.read(activeFontSourceProvider);

    try {
      for (final filePath in font.files) {
        final fileName = filePath.split('/').last;
        final stagingFilePath = p.join(stagingDir.path, fileName);

        int currentFileDownloaded = 0;
        final fileUrl = resolveFontFileUrl(activeSource.manifestUrl, filePath);

        await dio.download(
          fileUrl,
          stagingFilePath,
          cancelToken: cancelToken,
          options: Options(
            headers: {
              HttpHeaders.acceptEncodingHeader: 'identity',
            },
          ),
          onReceiveProgress: (received, _) {
            currentFileDownloaded = received;
            final aggregateReceived =
                previousFilesBytes + currentFileDownloaded;
            final progress =
                (aggregateReceived / totalBytes).clamp(0.0, 1.0);
            state = {
              ...state,
              fontId: state[fontId]!.copyWith(progress: progress),
            };
          },
        );

        final downloadedFile = File(stagingFilePath);
        if (await downloadedFile.exists()) {
          previousFilesBytes += await downloadedFile.length();
        }
      }

      // Atomic commit: move all staging files into targetDir
      final downloadedEntities = await stagingDir.list().toList();
      for (final entity in downloadedEntities) {
        if (entity is File) {
          final destPath = p.join(targetDir.path, p.basename(entity.path));
          final destFile = File(destPath);
          if (await destFile.exists()) {
            await destFile.delete();
          }
          try {
            await entity.rename(destPath);
          } catch (_) {
            // Fallback for cross-device partitions (EXDEV)
            await entity.copy(destPath);
            await entity.delete();
          }
        }
      }

      // Clean up staging directory
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }

      state = {
        ...state,
        fontId: state[fontId]!.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
        ),
      };
    } catch (e) {
      // Purge staging on failure or cancel
      try {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
      } catch (_) {}

      if (e is DioException && e.type == DioExceptionType.cancel) {
        return;
      }

      state = {
        ...state,
        fontId: state[fontId]!.copyWith(
          status: DownloadStatus.failed,
          error: e.toString(),
        ),
      };
    } finally {
      ref.read(fontListProvider.notifier).refresh();
    }
  }

  void pauseDownload(String fontId) {
    final download = state[fontId];
    if (download != null && download.status == DownloadStatus.downloading) {
      download.cancelToken?.cancel('Download paused');
      state = {
        ...state,
        fontId: download.copyWith(status: DownloadStatus.paused),
      };
    }
  }

  void resumeDownload(RemoteFontModel font) {
    final fontId = font.id;
    final download = state[fontId];
    if (download != null && download.status == DownloadStatus.paused) {
      startDownload(font);
    }
  }

  void cancelDownload(String fontId) {
    final download = state[fontId];
    if (download != null && download.status == DownloadStatus.downloading) {
      download.cancelToken?.cancel('Download canceled');
      state = {
        ...state,
        fontId: download.copyWith(status: DownloadStatus.none, progress: 0.0),
      };
    }
  }

  bool isDownloaded(String fontId, String filePath) {
    final fontDir = getFontDir();
    final fileName = filePath.split('/').last;
    final namespacedFile =
        File(p.join(fontDir.path, 'downloaded', fontId, fileName));
    final legacyFile = File(p.join(fontDir.path, fileName));
    return namespacedFile.existsSync() || legacyFile.existsSync();
  }
}
