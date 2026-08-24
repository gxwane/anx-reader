import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> checkUpdate(bool manualCheck) async {
  if (!EnvVar.enableManualReleaseLink) {
    return;
  }
  if (!manualCheck && !EnvVar.enableAutomaticUpdateCheck) {
    return;
  }

  // Rate-limit automatic checks to once per day
  if (!manualCheck &&
      DateTime.now().difference(Prefs().lastShowUpdate) <
          const Duration(days: 1)) {
    return;
  }
  Prefs().lastShowUpdate = DateTime.now();

  final BuildContext context = navigatorKey.currentContext!;
  Response response;
  try {
    response = await Dio().get(
      AppIdentity.releasesApiUrl,
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
  } catch (e) {
    if (manualCheck && context.mounted) {
      AnxToast.show(L10n.of(context).commonFailed);
    }
    AnxLog.severe('Update: Failed to check for updates $e');
    return;
  }

  final String tagName = response.data['tag_name'].toString();
  // GitHub tags are typically "v1.2.3" — strip the leading 'v'
  final String newVersion =
      tagName.startsWith('v') ? tagName.substring(1) : tagName;
  final String currentVersion = (await getAppVersion()).split('+').first;
  AnxLog.info('Update: current=$currentVersion, latest=$newVersion');

  final List<String> newParts = newVersion.split('.');
  final List<String> curParts = currentVersion.split('.');
  bool needUpdate = false;
  for (int i = 0; i < newParts.length; i++) {
    if (i >= curParts.length) {
      needUpdate = true;
      break;
    }
    final int newVer = int.tryParse(newParts[i]) ?? 0;
    final int curVer = int.tryParse(curParts[i]) ?? 0;
    if (newVer > curVer) {
      needUpdate = true;
      break;
    } else if (newVer < curVer) {
      break;
    }
  }

  if (!context.mounted) return;

  if (needUpdate) {
    // Close About dialog before showing update dialog (manual check only)
    if (manualCheck) {
      Navigator.of(context).pop();
    }
    SmartDialog.show(
      builder: (BuildContext context) {
        final String body = response.data['body']?.toString() ?? '';
        return AlertDialog(
          title: Text(
            L10n.of(context).commonNewVersion,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: StyledMarkdown(
              data: '### ${L10n.of(context).updateNewVersion} $newVersion\n\n'
                  '${L10n.of(context).updateCurrentVersion} $currentVersion\n\n'
                  '$body',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: SmartDialog.dismiss,
              child: Text(L10n.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () {
                launchUrl(
                  Uri.parse(AppIdentity.releasesUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: Text(L10n.of(context).updateViaGithub),
            ),
          ],
        );
      },
    );
  } else {
    if (manualCheck) {
      AnxToast.show(L10n.of(context).commonNoNewVersion);
    }
  }
}
