import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/get_current_language_code.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/utils/log/common.dart';

/// Changelog screen for showing app updates
/// Displays version history and new features
class ChangelogScreen extends StatefulWidget {
  final String lastVersion;
  final String currentVersion;
  final VoidCallback onComplete;
  final bool isDialog;

  const ChangelogScreen({
    super.key,
    required this.lastVersion,
    required this.currentVersion,
    required this.onComplete,
    this.isDialog = false,
  });

  /// Responsive adaptive presentation entry point
  static Future<void> show(
    BuildContext context, {
    required String lastVersion,
    required String currentVersion,
    VoidCallback? onComplete,
  }) async {
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;
    if (isDesktop) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        barrierDismissible: true,
        builder: (dialogContext) => ChangelogScreen(
          lastVersion: lastVersion,
          currentVersion: currentVersion,
          isDialog: true,
          onComplete: () => Navigator.of(dialogContext).pop(),
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (pageContext) => ChangelogScreen(
            lastVersion: lastVersion,
            currentVersion: currentVersion,
            isDialog: false,
            onComplete: () => Navigator.of(pageContext).pop(),
          ),
        ),
      );
    }
    onComplete?.call();
  }

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  String _changelogContent = '';
  bool _isLoading = true;
  late final ScrollController _scrollController = ScrollController();

  String get currentVersion => widget.currentVersion.split('+').first;
  String get lastVersion => widget.lastVersion.split('+').first;

  bool _initialized = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadChangelog();
    }
  }

  Future<void> _loadChangelog() async {
    try {
      // Load changelog from assets
      final String fullChangelog =
          await DefaultAssetBundle.of(context).loadString('assets/CHANGELOG.md');
      _changelogContent =
          extractVersionChangelog(fullChangelog, currentVersion);
    } catch (e) {
      AnxLog.warning('Failed to load changelog from assets: $e');
      _changelogContent = defaultChangelogContent;
    } finally {
      final bool isZh = getCurrentLanguageCode().startsWith('zh');
      _changelogContent =
          processChangelogContent(_changelogContent, isChinese: isZh);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDialog) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildDesktopLayout(context),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).whatsNew),
        elevation: 0,
        actions: [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 600;
                return isDesktop
                    ? _buildDesktopLayout(context)
                    : _buildMobileLayout(context);
              },
            ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: widget.isDialog
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 900),
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, isDesktop: true),
                const Divider(height: 1, thickness: 1),
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: StyledMarkdown(data: _changelogContent),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                _buildBottomBar(context, isDesktop: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, isDesktop: false),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: StyledMarkdown(data: _changelogContent),
              ),
            ),
          ),
        ),
        _buildBottomBar(context, isDesktop: false),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isDesktop}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool hasMigration =
        lastVersion.isNotEmpty && lastVersion != currentVersion;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: isDesktop ? 20 : 16,
      ),
      color: isDesktop
          ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.4)
          : colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: colorScheme.onPrimaryContainer,
              size: isDesktop ? 28 : 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'v$currentVersion',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    if (hasMigration) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          L10n.of(context).updateFromVersion(lastVersion),
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  L10n.of(context).welcomeToVersion(currentVersion),
                  style: TextStyle(
                    fontSize: isDesktop ? 20 : 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (widget.isDialog || isDesktop)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, {required bool isDesktop}) {
    final okButton = FilledButton(
      onPressed: _onComplete,
      style: isDesktop
          ? FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            )
          : null,
      child: Text(L10n.of(context).commonOk),
    );

    if (isDesktop) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: 140,
              height: 42,
              child: okButton,
            ),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: okButton,
      ),
    );
  }

  void _onComplete() {
    widget.onComplete();
  }
}

const String defaultChangelogContent = '''
- Fixed some bugs
- 修复已知问题
''';

/// Pure function to extract the relevant version block from the full changelog.
@visibleForTesting
String extractVersionChangelog(String fullChangelog, String targetVersion) {
  final cleanVersion = targetVersion.split('+').first.trim();
  final baseSemverMatch = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(cleanVersion);
  final baseSemver = baseSemverMatch?.group(1);

  final lines = fullChangelog.split('\n');

  // Delimiter must be closing bracket ']', whitespace '\s', or end-of-line '$'.
  // Do NOT include '-' or '\b' to prevent base semver (0.1.0) falsely matching pre-release (0.1.0-preview.5).
  int findVersionStart(String ver) {
    final pattern = RegExp(
      r'^##\s+\[?' + RegExp.escape(ver) + r'(\]|\s|$)',
      caseSensitive: false,
    );
    return lines.indexWhere((line) => pattern.hasMatch(line.trim()));
  }

  // Tier 1: Match full clean version (e.g. "0.1.0-preview.5")
  int startIndex = -1;
  if (cleanVersion.isNotEmpty) {
    startIndex = findVersionStart(cleanVersion);
  }

  // Tier 2: Match base semver if clean version was pre-release (e.g. "0.1.0")
  if (startIndex == -1 && baseSemver != null && baseSemver != cleanVersion) {
    startIndex = findVersionStart(baseSemver);
  }

  // Tier 3: Fallback to first available '## ' section (dev / nightly builds)
  if (startIndex == -1) {
    startIndex =
        lines.indexWhere((line) => RegExp(r'^##\s+').hasMatch(line.trim()));
    if (startIndex != -1) {
      AnxLog.info(
        'Version $targetVersion not explicitly matched in changelog; showing latest section: ${lines[startIndex].trim()}',
      );
    }
  }

  if (startIndex == -1) {
    AnxLog.warning('No version section found in changelog for $targetVersion');
    return defaultChangelogContent;
  }

  // Find the end of this version section (next '## ' header or EOF)
  int endIndex = lines.length;
  for (int i = startIndex + 1; i < lines.length; i++) {
    if (RegExp(r'^##\s+').hasMatch(lines[i].trim())) {
      endIndex = i;
      break;
    }
  }

  final versionContent =
      lines.sublist(startIndex + 1, endIndex).join('\n').trim();
  return versionContent.isEmpty ? defaultChangelogContent : versionContent;
}

/// Pure function to separate and select content based on locale.
@visibleForTesting
String processChangelogContent(String content, {required bool isChinese}) {
  final lines = content.split('\n');
  final chineseRegex = RegExp(r'[\u4e00-\u9fa5]');
  final englishLines = <String>[];
  final chineseLines = <String>[];

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('- ') && !line.startsWith('* ')) continue;

    if (chineseRegex.hasMatch(line)) {
      chineseLines.add(line);
    } else {
      englishLines.add(line);
    }
  }

  if (isChinese) {
    final selected = chineseLines.isNotEmpty ? chineseLines : englishLines;
    return selected.join('\n');
  } else {
    final selected = englishLines.isNotEmpty ? englishLines : chineseLines;
    return selected.join('\n');
  }
}
