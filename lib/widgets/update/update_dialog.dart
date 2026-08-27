import 'dart:io';

import 'package:anx_reader/config/app_identity.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/utils/check_update.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateDialog extends StatefulWidget {
  final ReleaseInfo releaseInfo;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.releaseInfo,
    required this.currentVersion,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  String _downloadSpeed = '';
  String? _downloadError;
  String? _downloadedFilePath;
  CancelToken? _cancelToken;

  int _lastReceivedBytes = 0;
  DateTime _lastSpeedCheckTime = DateTime.now();

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  void _onReceiveProgress(int received, int total) {
    if (!mounted) return;
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastSpeedCheckTime).inMilliseconds;

    if (elapsedMs >= 500) {
      final bytesDiff = received - _lastReceivedBytes;
      final speedBytesPerSec = (bytesDiff / (elapsedMs / 1000.0));
      _downloadSpeed = _formatSpeed(speedBytesPerSec);
      _lastReceivedBytes = received;
      _lastSpeedCheckTime = now;
    }

    setState(() {
      if (total > 0) {
        _downloadProgress = received / total;
        final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
        final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
        _downloadStatus = '$receivedMb MB / $totalMb MB';
      } else {
        final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
        _downloadStatus = '$receivedMb MB';
      }
    });
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    } else if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  Future<void> _startDownload() async {
    final asset = widget.releaseInfo.primaryAsset;
    if (asset == null) {
      launchUrl(
        Uri.parse(widget.releaseInfo.htmlUrl.isNotEmpty
            ? widget.releaseInfo.htmlUrl
            : AppIdentity.releasesUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = '0 MB / ${(asset.size / (1024 * 1024)).toStringAsFixed(1)} MB';
      _downloadSpeed = '';
      _downloadError = null;
      _downloadedFilePath = null;
      _cancelToken = CancelToken();
      _lastReceivedBytes = 0;
      _lastSpeedCheckTime = DateTime.now();
    });

    try {
      final filePath = await downloadReleaseAsset(
        asset,
        onProgress: _onReceiveProgress,
        cancelToken: _cancelToken!,
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _downloadedFilePath = filePath;
        _downloadProgress = 1.0;
      });

      // Trigger installation immediately
      await triggerInstall(filePath);
    } catch (e) {
      if (!mounted) return;
      if (DioExceptionType.cancel == (e is DioException ? e.type : null)) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = '';
        });
      } else {
        setState(() {
          _isDownloading = false;
          _downloadError = e.toString();
        });
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    setState(() {
      _isDownloading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: _buildTitle(context, theme, l10n),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, minWidth: 320),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.releaseInfo.isPrerelease)
                _buildBetaWarningBanner(context, theme, l10n),
              _buildVersionSection(theme, l10n),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              if (widget.releaseInfo.body.isNotEmpty)
                StyledMarkdown(data: widget.releaseInfo.body),
              if (_hasDownloadActivity)
                _buildDownloadSection(theme, l10n),
            ],
          ),
        ),
      ),
      actions: _buildDialogActions(l10n),
    );
  }

  bool get _hasDownloadActivity =>
      _isDownloading || _downloadedFilePath != null || _downloadError != null;

  Widget _buildTitle(BuildContext context, ThemeData theme, L10n l10n) {
    final isPrerelease = widget.releaseInfo.isPrerelease;
    return Row(
      children: [
        Icon(
          isPrerelease ? Icons.science_outlined : Icons.system_update_alt,
          color: isPrerelease ? Colors.orange : theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.commonNewVersion,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (isPrerelease) _buildPreviewBadge(l10n),
      ],
    );
  }

  Widget _buildPreviewBadge(L10n l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withAlpha(120)),
      ),
      child: Text(
        l10n.updateChannelPreview,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.orange,
        ),
      ),
    );
  }

  Widget _buildBetaWarningBanner(
      BuildContext context, ThemeData theme, L10n l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.updatePreviewWarningBanner,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.backup_outlined, size: 16),
                label: Text(l10n.updateBackupNow),
                onPressed: () {
                  SmartDialog.dismiss();
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const SyncSetting(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionSection(ThemeData theme, L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${l10n.updateCurrentVersion} ${widget.currentVersion}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${l10n.updateNewVersion} ${widget.releaseInfo.version}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadSection(ThemeData theme, L10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        if (_isDownloading)
          _buildActiveDownloadState(theme, l10n)
        else if (_downloadedFilePath != null)
          _buildDownloadCompleteState(l10n)
        else if (_downloadError != null)
          _buildDownloadErrorState(l10n),
      ],
    );
  }

  Widget _buildActiveDownloadState(ThemeData theme, L10n l10n) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.updateDownloading,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _downloadProgress > 0 ? _downloadProgress : null,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_downloadStatus, style: theme.textTheme.bodySmall),
            if (_downloadSpeed.isNotEmpty)
              Text(
                _downloadSpeed,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadCompleteState(L10n l10n) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.updateDownloadSuccess,
            style: const TextStyle(color: Colors.green),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadErrorState(L10n l10n) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${l10n.updateDownloadFailed}: $_downloadError',
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDialogActions(L10n l10n) {
    if (_isDownloading) {
      return [
        TextButton(
          onPressed: _cancelDownload,
          child: Text(l10n.updateCancelDownload),
        ),
      ];
    }

    final primaryAsset = widget.releaseInfo.primaryAsset;
    final canDownloadDirectly =
        primaryAsset != null && (Platform.isAndroid || Platform.isWindows);

    return [
      TextButton(
        onPressed: SmartDialog.dismiss,
        child: Text(l10n.commonCancel),
      ),
      TextButton(
        onPressed: _openReleasePage,
        child: Text(l10n.updateViaGithub),
      ),
      if (_downloadedFilePath != null)
        FilledButton.icon(
          onPressed: () => triggerInstall(_downloadedFilePath!),
          icon: const Icon(Icons.install_mobile, size: 18),
          label: Text(l10n.updateInstallNow),
        )
      else if (_downloadError != null)
        FilledButton.icon(
          onPressed: _startDownload,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.updateRetryDownload),
        )
      else if (canDownloadDirectly)
        FilledButton.icon(
          onPressed: _startDownload,
          icon: const Icon(Icons.download, size: 18),
          label: Text(l10n.updateDownloadNow),
        ),
    ];
  }

  void _openReleasePage() {
    launchUrl(
      Uri.parse(widget.releaseInfo.htmlUrl.isNotEmpty
          ? widget.releaseInfo.htmlUrl
          : AppIdentity.releasesUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}

