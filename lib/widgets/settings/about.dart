import 'dart:async';

import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/settings/link_icon.dart';
import 'package:anx_reader/utils/check_update.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anx_reader/enums/update_channel.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:url_launcher/url_launcher.dart';

class About extends StatefulWidget {
  const About({
    super.key,
    this.leadingColor = false,
  });
  final bool leadingColor;

  @override
  State<About> createState() => _AboutState();
}

class _AboutState extends State<About> {
  String version = '';

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {}

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(L10n.of(context).appAbout),
      leading: Icon(Icons.info_outline,
          color: widget.leadingColor
              ? Theme.of(context).colorScheme.primary
              : null),
      onTap: () => openAboutDialog(),
    );
  }
}

const int _developerUnlockTapThreshold = 7;
int _developerUnlockTapCount = 0;
Timer? _developerUnlockResetTimer;

void _handleDeveloperUnlockTap(BuildContext context) {
  _developerUnlockTapCount++;
  _developerUnlockResetTimer?.cancel();
  _developerUnlockResetTimer =
      Timer(const Duration(seconds: 2), () => _developerUnlockTapCount = 0);

  final alreadyEnabled = Prefs().developerOptionsEnabled;
  if (_developerUnlockTapCount < _developerUnlockTapThreshold) {
    return;
  }

  _developerUnlockTapCount = 0;
  if (!alreadyEnabled) {
    Prefs().developerOptionsEnabled = true;
    AnxToast.show('Developer options enabled');
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
  Future.microtask(_openDeveloperOptionsPage);
}

void _openDeveloperOptionsPage() {
  final BuildContext? navContext = navigatorKey.currentContext;
  if (navContext == null) return;
  Navigator.of(navContext).push(
    CupertinoPageRoute(
      fullscreenDialog: false,
      builder: (context) => const DeveloperOptionsPage(),
    ),
  );
}

Future<void> _showSwitchPreviewWarning(
    BuildContext context, StateSetter setDialogState) async {
  final l10n = L10n.of(context);
  await showDialog(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.updateChannelSwitchPreviewWarningTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(l10n.updateChannelSwitchPreviewWarningBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Prefs().updateChannel = UpdateChannel.preview;
              Navigator.of(ctx).pop();
              setDialogState(() {});
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      );
    },
  );
}

Future<void> _showUpdateChannelSelector(
    BuildContext context, StateSetter setDialogState) async {
  final l10n = L10n.of(context);
  final currentChannel = Prefs().updateChannel;

  await showDialog(
    context: context,
    builder: (BuildContext ctx) {
      return SimpleDialog(
        title: Text(l10n.updateChannel),
        children: [
          RadioListTile<UpdateChannel>(
            title: Text(l10n.updateChannelStable),
            value: UpdateChannel.stable,
            groupValue: currentChannel,
            onChanged: (val) {
              if (val != null) {
                Prefs().updateChannel = val;
                Navigator.of(ctx).pop();
                setDialogState(() {});
              }
            },
          ),
          RadioListTile<UpdateChannel>(
            title: Text(l10n.updateChannelPreview),
            value: UpdateChannel.preview,
            groupValue: currentChannel,
            onChanged: (val) {
              if (val != null) {
                Navigator.of(ctx).pop();
                if (currentChannel != UpdateChannel.preview) {
                  _showSwitchPreviewWarning(context, setDialogState);
                }
              }
            },
          ),
        ],
      );
    },
  );
}

Future<void> openAboutDialog() async {
  final pubspecContent = await rootBundle.loadString('pubspec.yaml');
  final pubspec = Pubspec.parse(pubspecContent);
  final version = pubspec.version.toString();

  showDialog(
    context: navigatorKey.currentContext!,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          final currentChannel = Prefs().updateChannel;
          final channelText = currentChannel == UpdateChannel.stable
              ? L10n.of(context).updateChannelStable
              : L10n.of(context).updateChannelPreview;

          return AlertDialog(
              content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500,
              minWidth: 300,
            ),
            child: SingleChildScrollView(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 5),
                      child: Center(
                        child: Text(
                          AppIdentity.displayName,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: Icon(
                          Icons.fork_right,
                          color:
                              Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                        title: Text(L10n.of(context).aboutForkStatusTitle),
                        subtitle: Text(L10n.of(context).aboutForkStatusBody),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      title: Text(L10n.of(context).appVersion),
                      subtitle: Text(version + (kDebugMode ? ' (debug)' : '')),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: version));
                        AnxToast.show(L10n.of(context).notesPageCopied);
                        _handleDeveloperUnlockTap(context);
                      },
                    ),
                    ListTile(
                      title: Text(L10n.of(context).updateChannel),
                      subtitle: Text(channelText),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _showUpdateChannelSelector(context, setDialogState),
                    ),
                    if (EnvVar.enableManualReleaseLink)
                      ListTile(
                          title: Text(L10n.of(context).aboutCheckForUpdates),
                          onTap: () => checkUpdate(true)),
                    ListTile(
                      title: Text(L10n.of(context).appLicense),
                      onTap: () {
                        showLicensePage(
                          context: context,
                          applicationName: AppIdentity.displayName,
                          applicationVersion: version,
                        );
                      },
                    ),
                    ListTile(
                      title: Text(L10n.of(context).appAuthor),
                      onTap: () {
                        launchUrl(
                          Uri.parse(
                              '${AppIdentity.repositoryUrl}/graphs/contributors'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    ListTile(
                      title: const Text('Upstream Anx Reader'),
                      subtitle: Text(AppIdentity.upstreamRepositoryUrl),
                      onTap: () {
                        launchUrl(
                          Uri.parse(AppIdentity.upstreamRepositoryUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    ListTile(
                      title: Text(L10n.of(context).aboutPrivacyPolicy),
                      onTap: () async {
                        launchUrl(
                          Uri.parse(
                              '${AppIdentity.repositoryUrl}/blob/develop/docs/privacy-policy.md'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    ListTile(
                      title: Text(L10n.of(context).aboutTermsOfUse),
                      onTap: () async {
                        launchUrl(
                          Uri.parse(
                              '${AppIdentity.repositoryUrl}/blob/develop/LICENSE'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    ListTile(
                      title: Text(L10n.of(context).aboutHelp),
                      onTap: () async {
                        launchUrl(
                          Uri.parse(AppIdentity.documentationUrl),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    const Divider(),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          linkIcon(
                              icon: Icon(
                                IonIcons.logo_github,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              url: AppIdentity.repositoryUrl,
                              mode: LaunchMode.externalApplication),
                          linkIcon(
                              icon: Icon(
                                Icons.fork_right,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              url: AppIdentity.upstreamRepositoryUrl,
                              mode: LaunchMode.externalApplication),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
        },
      );
    },
  );
}
