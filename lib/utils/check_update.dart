import 'dart:io';

import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/update_channel.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/update/update_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name']?.toString() ?? '',
      downloadUrl: json['browser_download_url']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReleaseInfo {
  final String tagName;
  final AppVersion version;
  final bool isPrerelease;
  final String title;
  final String body;
  final String htmlUrl;
  final List<ReleaseAsset> assets;

  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.isPrerelease,
    required this.title,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name']?.toString() ?? '';
    final assetsJson = json['assets'] as List<dynamic>? ?? [];
    final assets = assetsJson
        .map((a) => ReleaseAsset.fromJson(a as Map<String, dynamic>))
        .toList();

    return ReleaseInfo(
      tagName: tagName,
      version: AppVersion.parse(tagName),
      isPrerelease: json['prerelease'] == true,
      title: json['name']?.toString() ?? tagName,
      body: json['body']?.toString() ?? '',
      htmlUrl: json['html_url']?.toString() ?? '',
      assets: assets,
    );
  }

  ReleaseAsset? get primaryAsset {
    if (assets.isEmpty) return null;
    if (Platform.isAndroid) {
      final arm64 = assets
          .where((a) => a.name.endsWith('.apk') && a.name.contains('arm64-v8a'))
          .firstOrNull;
      if (arm64 != null) return arm64;
      final universal = assets
          .where((a) => a.name.endsWith('.apk') && a.name.contains('universal'))
          .firstOrNull;
      if (universal != null) return universal;
      return assets.where((a) => a.name.endsWith('.apk')).firstOrNull;
    } else if (Platform.isWindows) {
      return assets.where((a) => a.name.endsWith('.exe')).firstOrNull;
    } else if (Platform.isMacOS) {
      return assets.where((a) => a.name.endsWith('.dmg')).firstOrNull ??
          assets.where((a) => a.name.endsWith('.zip')).firstOrNull;
    } else if (Platform.isLinux) {
      return assets.where((a) => a.name.endsWith('.AppImage')).firstOrNull ??
          assets.where((a) => a.name.endsWith('.deb')).firstOrNull;
    }
    return assets.firstOrNull;
  }
}

const Map<String, String> githubHeaders = {
  'Accept': 'application/vnd.github+json',
  'User-Agent': 'AnxReader-GX-Preview',
  'X-GitHub-Api-Version': '2022-11-28',
};

bool isRateLimitError(dynamic error) {
  if (error is DioException) {
    if (error.response?.statusCode == 403) return true;
    final message = error.message?.toLowerCase() ?? '';
    if (message.contains('rate limit') || message.contains('403')) return true;
  }
  return false;
}

Future<void> showRateLimitDialog(BuildContext context) async {
  if (!context.mounted) return;
  final l10n = L10n.of(context);
  await showDialog(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.updateRateLimitTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(l10n.updateRateLimitExceeded),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse(AppIdentity.releasesUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l10n.updateViaGithub),
          ),
        ],
      );
    },
  );
}

Future<ReleaseInfo?> fetchLatestRelease(UpdateChannel channel) async {
  final dio = Dio();
  final options = Options(headers: githubHeaders);

  if (channel == UpdateChannel.preview) {
    final response = await dio.get(
      AppIdentity.releasesListApiUrl,
      options: options,
    );
    final list = response.data as List<dynamic>;
    if (list.isEmpty) return null;
    return ReleaseInfo.fromJson(list.first as Map<String, dynamic>);
  } else {
    try {
      final response = await dio.get(
        AppIdentity.releasesApiUrl,
        options: options,
      );
      return ReleaseInfo.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      final response = await dio.get(
        AppIdentity.releasesListApiUrl,
        options: options,
      );
      final list = response.data as List<dynamic>;
      for (final item in list) {
        final r = ReleaseInfo.fromJson(item as Map<String, dynamic>);
        if (!r.isPrerelease) return r;
      }
      return null;
    }
  }
}

Future<String> downloadReleaseAsset(
  ReleaseAsset asset, {
  required ProgressCallback onProgress,
  required CancelToken cancelToken,
}) async {
  final tempDir = await getTemporaryDirectory();
  final savePath = p.join(tempDir.path, asset.name);

  final file = File(savePath);
  if (await file.exists()) {
    await file.delete();
  }

  await Dio().download(
    asset.downloadUrl,
    savePath,
    onReceiveProgress: onProgress,
    cancelToken: cancelToken,
  );

  return savePath;
}

Future<void> triggerInstall(String filePath) async {
  try {
    if (Platform.isAndroid) {
      const channel =
          MethodChannel('io.github.gxwane.anx_reader_gx_preview/install_info');
      await channel.invokeMethod('installApk', {'filePath': filePath});
    } else if (Platform.isWindows) {
      await Process.start(filePath, []);
    } else {
      await launchUrl(Uri.file(filePath));
    }
  } catch (e) {
    AnxLog.severe('Failed to trigger installation: $e');
    await launchUrl(Uri.parse(AppIdentity.releasesUrl),
        mode: LaunchMode.externalApplication);
  }
}

Future<void> checkUpdate(bool manualCheck) async {
  if (!EnvVar.enableManualReleaseLink) {
    return;
  }
  if (!manualCheck && !EnvVar.enableAutomaticUpdateCheck) {
    return;
  }

  if (!manualCheck &&
      DateTime.now().difference(Prefs().lastShowUpdate) <
          const Duration(days: 1)) {
    return;
  }
  Prefs().lastShowUpdate = DateTime.now();

  final BuildContext context = navigatorKey.currentContext!;
  ReleaseInfo? releaseInfo;
  try {
    releaseInfo = await fetchLatestRelease(Prefs().updateChannel);
  } catch (e) {
    AnxLog.severe('Update: Failed to check for updates $e');
    if (!context.mounted) return;
    if (manualCheck) {
      if (isRateLimitError(e)) {
        await showRateLimitDialog(context);
      } else {
        AnxToast.show(L10n.of(context).commonFailed);
      }
    }
    return;
  }

  if (releaseInfo == null) {
    if (manualCheck && context.mounted) {
      AnxToast.show(L10n.of(context).commonNoNewVersion);
    }
    return;
  }

  final currentAppVersion = await getCurrentAppVersion();
  final currentVersionStr = currentAppVersion.toString();
  final newVersion = releaseInfo.version;
  AnxLog.info(
      'Update: current=$currentVersionStr, latest=$newVersion, channel=${Prefs().updateChannel}');

  final bool needUpdate = newVersion > currentAppVersion;

  if (!context.mounted) return;

  if (needUpdate) {
    if (manualCheck) {
      Navigator.of(context).pop();
    }
    SmartDialog.show(
      builder: (BuildContext context) {
        return UpdateDialog(
          releaseInfo: releaseInfo!,
          currentVersion: currentVersionStr,
        );
      },
    );
  } else {
    if (manualCheck) {
      AnxToast.show(L10n.of(context).commonNoNewVersion);
    }
  }
}


