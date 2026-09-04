import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/backup/backup_service.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/sync_test_helper.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/webdav/test_webdav.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';

class SyncSetting extends ConsumerStatefulWidget {
  const SyncSetting({super.key});

  @override
  ConsumerState<SyncSetting> createState() => _SyncSettingState();
}

class _SyncSettingState extends ConsumerState<SyncSetting> {
  @override
  Widget build(BuildContext context) {
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncWebdav),
          tiles: [
            webdavSwitch(context, setState, ref),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                value: Text(Prefs().getSyncInfo(SyncProtocol.webdav)['url'] ??
                    'Not set'),
                // enabled: Prefs().webdavStatus,
                onPressed: (context) async {
                  showWebdavDialog(context);
                }),
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 20, 10),
                child: GestureDetector(
                  onTap: () async {
                    if (!await launchUrl(
                        Uri.parse(
                            '${AppIdentity.upstreamDocumentationUrl}/sync/webdav'),
                        mode: LaunchMode.externalApplication)) {
                      AnxToast.show(L10n.of(context).commonFailed);
                    }
                  },
                  child: Text(
                    L10n.of(context).settingsNarrateClickForHelp,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      decoration: TextDecoration.underline,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            SettingsTile(
                title: Text(L10n.of(context).settingsSyncWebdavSyncNow),
                leading: const Icon(Icons.sync_alt),
                // value: Text(Prefs().syncDirection),
                enabled: Prefs().webdavStatus,
                onPressed: (context) {
                  chooseDirection(ref);
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).webdavOnlyWifi),
                leading: const Icon(Icons.wifi),
                initialValue: Prefs().onlySyncWhenWifi,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().onlySyncWhenWifi = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncCompletedToast),
                leading: const Icon(Icons.notifications),
                initialValue: Prefs().syncCompletedToast,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncCompletedToast = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncAutoSync),
                leading: const Icon(Icons.sync),
                initialValue: Prefs().autoSync,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().autoSync = value;
                  });
                }),
            SettingsTile(
                title: Text(L10n.of(context).restoreBackup),
                leading: const Icon(Icons.restore),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showBackupManagementDialog();
                })
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncMarkdownNotesSection),
          tiles: [
            SettingsTile.switchTile(
              title: Text(L10n.of(context).settingsSyncAutoExportMarkdown),
              description: Text(
                L10n.of(context).settingsSyncAutoExportMarkdownSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              leading: const Icon(Icons.note_alt_outlined),
              initialValue: Prefs().autoExportMarkdownNotesToWebdav,
              enabled: Prefs().webdavStatus,
              onToggle: (bool value) {
                setState(() {
                  Prefs().autoExportMarkdownNotesToWebdav = value;
                });
              },
            ),
            SettingsTile(
              title: Text(L10n.of(context).settingsSyncExportAllMarkdownNow),
              leading: const Icon(Icons.drive_folder_upload_outlined),
              enabled: Prefs().webdavStatus,
              onPressed: (context) {
                _exportAllMarkdownNotes(context);
              },
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).exportAndImport),
          tiles: [
            SettingsTile(
                title: Text(L10n.of(context).exportAndImportExport),
                leading: const Icon(Icons.cloud_upload),
                onPressed: (context) {
                  exportData(context);
                }),
            SettingsTile(
                title: Text(L10n.of(context).exportAndImportImport),
                leading: const Icon(Icons.cloud_download),
                onPressed: (context) {
                  importData();
                }),
          ],
        ),
      ],
    );
  }

  Future<void> _exportAllMarkdownNotes(BuildContext context) async {
    if (!Prefs().webdavStatus) return;

    final l10n = L10n.of(context);
    final progressNotifier = ValueNotifier<(int current, int total)>((0, 0));

    SmartDialog.show(
      tag: 'markdown_export_progress',
      builder: (context) => ValueListenableBuilder<(int, int)>(
        valueListenable: progressNotifier,
        builder: (context, progress, _) => SimpleDialog(
          title: Center(
            child: Text(
              l10n.settingsSyncExportingMarkdown(progress.$1, progress.$2),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );

    try {
      final exportedCount = await Sync().exportAllMarkdownNotesToWebdav(
        onProgress: (curr, total) {
          progressNotifier.value = (curr, total);
        },
      );

      SmartDialog.dismiss(tag: 'markdown_export_progress');
      if (mounted) {
        AnxToast.show(l10n.settingsSyncExportAllMarkdownSuccess(exportedCount));
      }
    } catch (e) {
      SmartDialog.dismiss(tag: 'markdown_export_progress');
      if (mounted) {
        AnxToast.show(l10n.commonFailed);
      }
    } finally {
      progressNotifier.dispose();
    }
  }

  void _showDataDialog(String title) {
    Future.microtask(() {
      SmartDialog.show(
        builder: (BuildContext context) => SimpleDialog(
          title: Center(child: Text(title)),
          children: const [
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    });
  }

  Future<void> exportData(BuildContext context) async {
    AnxLog.info('exportData: start');
    if (!mounted) return;

    _showDataDialog(L10n.of(context).exporting);

    String? zipPath;
    try {
      final exportResult = await BackupService().createExport();
      zipPath = exportResult.zipPath;
      final file = File(exportResult.zipPath);
      if (!await file.exists()) {
        throw StateError('Backup zip was not created');
      }

      final saveStopwatch = Stopwatch()..start();
      final filePath = await saveFileToDownload(
        sourceFilePath: file.path,
        fileName: exportResult.fileName,
        mimeType: 'application/zip',
      );
      AnxLog.info(
        'exportData: save completed in ${saveStopwatch.elapsedMilliseconds}ms',
      );

      if (filePath != null) {
        AnxLog.info('exportData: Saved to: $filePath');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).exportTo(filePath));
      } else {
        AnxLog.info('exportData: Cancelled');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).commonCanceled);
      }
    } catch (e, stackTrace) {
      AnxLog.severe('exportData: failed: $e', e, stackTrace);
      AnxToast.show(L10n.of(navigatorKey.currentContext!).commonFailed);
    } finally {
      SmartDialog.dismiss();
      if (zipPath != null) {
        final zipFile = File(zipPath);
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      }
    }
  }

  Future<void> importData() async {
    AnxLog.info('importData: start');
    if (!mounted) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null) {
      return;
    }

    String? filePath = result.files.single.path;
    if (filePath == null) {
      AnxLog.info('importData: cannot get file path');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }

    File zipFile = File(filePath);
    if (!await zipFile.exists()) {
      AnxLog.info('importData: zip file not found');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }
    _showDataDialog(L10n.of(navigatorKey.currentContext!).importing);
    try {
      await BackupService().importFromZip(zipFile.path);
      AnxLog.info('importData: import success');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importSuccessRestartApp);
    } catch (e, stackTrace) {
      AnxLog.severe('importData: error while unzipping or copying files: $e', e,
          stackTrace);
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importFailed(e.toString()));
    } finally {
      SmartDialog.dismiss();
    }
  }
}

void showWebdavDialog(BuildContext context) {
  final title = L10n.of(context).settingsSyncWebdav;
  // final prefs = Prefs().saveWebdavInfo;
  final webdavInfo = Prefs().getSyncInfo(SyncProtocol.webdav);
  final webdavUrlController = TextEditingController(text: webdavInfo['url']);
  final webdavUsernameController =
      TextEditingController(text: webdavInfo['username']);
  final webdavPasswordController =
      TextEditingController(text: webdavInfo['password']);
  Widget buildTextField(String labelText, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        obscureText: labelText == L10n.of(context).settingsSyncWebdavPassword
            ? true
            : false,
        controller: controller,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
        ),
      ),
    );
  }

  showDialog(
    context: context,
    builder: (context) {
      return SimpleDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(20),
        children: [
          buildTextField(
              L10n.of(context).settingsSyncWebdavUrl, webdavUrlController),
          buildTextField(L10n.of(context).settingsSyncWebdavUsername,
              webdavUsernameController),
          buildTextField(L10n.of(context).settingsSyncWebdavPassword,
              webdavPasswordController),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => SyncTestHelper.handleFullTestConnection(
                  context,
                  protocol: SyncProtocol.webdav,
                  config: {
                    'url': webdavUrlController.text.trim(),
                    'username': webdavUsernameController.text,
                    'password': webdavPasswordController.text,
                  },
                ),
                icon: const Icon(Icons.wifi_find),
                label: Text(L10n.of(context).settingsSyncWebdavTestConnection),
              ),
              TextButton(
                onPressed: () {
                  webdavInfo['url'] = webdavUrlController.text.trim();
                  webdavInfo['username'] = webdavUsernameController.text;
                  webdavInfo['password'] = webdavPasswordController.text;
                  Prefs().setSyncInfo(SyncProtocol.webdav, webdavInfo);
                  SyncClientFactory.initializeCurrentClient();
                  Navigator.pop(context);
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          ),
        ],
      );
    },
  );
}
