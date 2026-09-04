import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/providers/fonts.dart';
import 'package:anx_reader/service/font/system_font_service.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

class FontsSettingPage extends ConsumerWidget {
  const FontsSettingPage({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).fontManagement),
          bottom: TabBar(
            indicatorColor: theme.colorScheme.primary,
            tabs: [
              Tab(
                icon: const Icon(Icons.bookmark_outline),
                text: L10n.of(context).fontTabMyFonts,
              ),
              Tab(
                icon: const Icon(Icons.devices),
                text: L10n.of(context).fontTabSystemFonts,
              ),
              Tab(
                icon: const Icon(Icons.cloud_download_outlined),
                text: L10n.of(context).fontTabOnlineFonts,
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MyFontsTab(),
            _SystemFontsTab(),
            _OnlineFontsTab(),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Tab 1: 我的字体 (My Fonts)
// ==========================================
class _MyFontsTab extends ConsumerStatefulWidget {
  const _MyFontsTab();

  @override
  ConsumerState<_MyFontsTab> createState() => _MyFontsTabState();
}

class _MyFontsTabState extends ConsumerState<_MyFontsTab> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontListAsync = ref.watch(fontListProvider);

    return fontListAsync.when(
      data: (fonts) {
        final activeFont = Prefs().font;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Top action banner for importing local fonts
            FilledContainer(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.file_upload_outlined, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.of(context).addNewFont,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          L10n.of(context).fontImportSupportedFormats,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final count =
                          await ref.read(fontListProvider.notifier).importFonts();
                      if (context.mounted && count > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text(L10n.of(context).fontImportSuccess(count)),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(L10n.of(context).addNewFont),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Fonts list
            ...fonts.map((font) {
              final isActive = font.id == activeFont.id;

              return Card(
                elevation: isActive ? 2 : 0,
                color: isActive
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isActive
                      ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
                      : BorderSide.none,
                ),
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: _fontIcon(font, theme),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          font.label,
                          style: TextStyle(
                            fontFamily: font.name,
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.normal,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _sourceBadge(font, theme, context),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '永和九年，歲在癸丑 The quick brown fox jumps',
                      style: TextStyle(
                        fontFamily: font.name,
                        fontSize: 13,
                        color: theme.hintColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive)
                        Chip(
                          avatar: const Icon(Icons.check, size: 14),
                          label: Text(
                            L10n.of(context).fontInUse,
                            style: const TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          side: BorderSide.none,
                        ),
                      if (font.source == FontSource.systemFont)
                        IconButton(
                          icon: const Icon(Icons.bookmark_remove_outlined),
                          tooltip: L10n.of(context).fontUnpin,
                          onPressed: () {
                            ref
                                .read(fontListProvider.notifier)
                                .togglePinSystemFont(font.name);
                          },
                        ),
                      if (font.isDeletable)
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          tooltip: L10n.of(context).fontDeleteConfirmTitle,
                          onPressed: () => _showDeleteDialog(context, ref, font),
                        ),
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      Prefs().font = font;
                    });
                    epubPlayerKey.currentState?.changeFont(font);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(L10n.of(context).fontSetSuccess(font.label)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('${L10n.of(context).fontFailedToLoadFonts}: $e'),
      ),
    );
  }

  Widget _fontIcon(FontModel font, ThemeData theme) {
    IconData icon;
    switch (font.source) {
      case FontSource.book:
        icon = Icons.menu_book;
        break;
      case FontSource.systemUi:
      case FontSource.systemFont:
        icon = Icons.devices;
        break;
      case FontSource.bundled:
        icon = Icons.star_outline;
        break;
      case FontSource.localCustom:
        icon = Icons.text_fields;
        break;
      case FontSource.downloaded:
        icon = Icons.cloud_done_outlined;
        break;
    }
    return Icon(icon, color: theme.colorScheme.primary);
  }

  Widget _sourceBadge(FontModel font, ThemeData theme, BuildContext context) {
    String text;
    switch (font.source) {
      case FontSource.book:
        return const SizedBox.shrink();
      case FontSource.systemUi:
        text = L10n.of(context).fontBadgeSystem;
        break;
      case FontSource.systemFont:
        text = L10n.of(context).fontBadgeSystem;
        break;
      case FontSource.bundled:
        text = L10n.of(context).fontBadgeBundled;
        break;
      case FontSource.localCustom:
        text = L10n.of(context).fontBadgeCustom;
        break;
      case FontSource.downloaded:
        text = L10n.of(context).fontBadgeDownloaded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    FontModel font,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(dialogContext).fontDeleteConfirmTitle),
        content:
            Text(L10n.of(dialogContext).fontDeleteConfirmContent(font.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.of(dialogContext).commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.of(dialogContext).commonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success =
          await ref.read(fontListProvider.notifier).deleteFont(font);
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).commonFailed)),
        );
      }
    }
  }
}

// ==========================================
// Tab 2: 系统字体库 (System Fonts)
// ==========================================
class _SystemFontsTab extends ConsumerStatefulWidget {
  const _SystemFontsTab();

  @override
  ConsumerState<_SystemFontsTab> createState() => _SystemFontsTabState();
}

class _SystemFontsTabState extends ConsumerState<_SystemFontsTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  List<String> _allSystemFonts = [];
  bool _isLoading = true;
  String _filterQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSystemFonts();
  }

  Future<void> _loadSystemFonts() async {
    final fonts = await SystemFontService.instance.getAvailableSystemFonts();
    if (mounted) {
      setState(() {
        _allSystemFonts = fonts;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final pinnedFonts = ref.watch(fontListProvider).when(
          data: (fonts) => Prefs().pinnedSystemFonts,
          loading: () => Prefs().pinnedSystemFonts,
          error: (_, __) => Prefs().pinnedSystemFonts,
        );
    final pinnedSet = pinnedFonts.toSet();

    final filteredFonts = _allSystemFonts.where((font) {
      if (_filterQuery.isEmpty) return true;
      return font.toLowerCase().contains(_filterQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: L10n.of(context).fontSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _filterQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _filterQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (val) => setState(() => _filterQuery = val.trim()),
          ),
        ),

        // System font list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredFonts.isEmpty
                  ? Center(
                      child: Text(
                        L10n.of(context).fontNoMatchingFonts,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredFonts.length,
                      itemBuilder: (context, index) {
                        final fontName = filteredFonts[index];
                        final isPinned = pinnedSet.contains(fontName);

                        return ListTile(
                          leading: Icon(
                            isPinned ? Icons.bookmark : Icons.bookmark_border,
                            color: isPinned ? theme.colorScheme.primary : null,
                          ),
                          title: Text(
                            fontName,
                            style: TextStyle(
                              fontFamily: fontName,
                              fontWeight:
                                  isPinned ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '永和九年，歲在癸丑，暮春之初 The quick brown fox jumps',
                            style: TextStyle(
                              fontFamily: fontName,
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton.icon(
                            icon: Icon(
                              isPinned ? Icons.check : Icons.add,
                              size: 16,
                            ),
                            label: Text(
                              isPinned
                                  ? L10n.of(context).fontPinned
                                  : L10n.of(context).fontPin,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: isPinned
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                            onPressed: () {
                              ref
                                  .read(fontListProvider.notifier)
                                  .togglePinSystemFont(fontName);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ==========================================
// Tab 3: 在线字体库 (Online Fonts Store)
// ==========================================
class _OnlineFontsTab extends ConsumerStatefulWidget {
  const _OnlineFontsTab();

  @override
  ConsumerState<_OnlineFontsTab> createState() => _OnlineFontsTabState();
}

class _OnlineFontsTabState extends ConsumerState<_OnlineFontsTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fontList = ref.watch(fontsProvider);

    return fontList.when(
      data: (fonts) {
        if (fonts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final filteredFonts = fonts.where((font) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return font.name.toLowerCase().contains(q) ||
              font.desc.toLowerCase().contains(q);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: L10n.of(context).fontSearchOnlineHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.trim());
                },
              ),
            ),
            Expanded(
              child: filteredFonts.isEmpty
                  ? Center(
                      child: Text(
                        L10n.of(context).fontNoMatchingFonts,
                        style: TextStyle(color: Theme.of(context).hintColor),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filteredFonts.length,
                      itemBuilder: (context, index) {
                        final font = filteredFonts[index];
                        final sizeStr = _formatFileSize(font.size);
                        return FilledContainer(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (font.preview.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: '$fontBaseUrl${font.preview}',
                                  width: MediaQuery.of(context).size.width,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.error),
                                ),
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            font.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (sizeStr.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              sizeStr,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(font.desc),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () {
                                            launchUrlString(
                                              font.official,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          },
                                          icon: const Icon(Icons.link),
                                          label: Text(
                                            L10n.of(context).fontOfficialWebsite,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .primaryColor,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () {
                                            launchUrlString(
                                              font.license.url,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          },
                                          icon: const Icon(Icons.link),
                                          label: Text(
                                            font.license.name,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .primaryColor,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildDownloadButton(context, font),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.of(context).fontFailedToLoadFonts),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(L10n.of(context).commonRetry),
              onPressed: () => ref.refresh(fontsProvider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton(
    BuildContext context,
    RemoteFontModel font,
  ) {
    final downloadState = ref.watch(fontDownloadsProvider)[font.id];
    final fontDownloads = ref.read(fontDownloadsProvider.notifier);
    final isAllFilesDownloaded =
        font.files.every((file) => fontDownloads.isDownloaded(font.id, file));

    if (isAllFilesDownloaded) {
      final activeFont = Prefs().font;
      final isCurrentActive =
          activeFont.path.contains('downloaded/${font.id}/') ||
              activeFont.name == font.name;

      if (isCurrentActive) {
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle, color: Colors.green),
          label: Text(
            L10n.of(context).fontInUse,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      }

      return FilledButton.icon(
        onPressed: () {
          final availableFonts =
              ref.read(fontListProvider).valueOrNull ?? [];
          final matchingFont = availableFonts.firstWhere(
            (m) =>
                m.path.contains('downloaded/${font.id}/') ||
                m.name == font.name,
            orElse: () {
              final fileName = font.files.firstOrNull?.split('/').last ?? '';
              return FontModel(
                id: 'downloaded:${font.id}',
                label: font.name,
                name: font.name,
                path: 'downloaded/${font.id}/$fileName',
                source: FontSource.downloaded,
              );
            },
          );

          setState(() {
            Prefs().font = matchingFont;
          });
          epubPlayerKey.currentState?.changeFont(matchingFont);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(L10n.of(context).fontSetSuccess(matchingFont.label)),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.check),
        label: Text(L10n.of(context).fontApply),
      );
    }

    if (downloadState != null) {
      switch (downloadState.status) {
        case DownloadStatus.downloading:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: downloadState.progress),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${L10n.of(context).fontDownloading((downloadState.progress * 100).toStringAsFixed(1))}%',
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => ref
                        .read(fontDownloadsProvider.notifier)
                        .pauseDownload(font.id),
                    icon: const Icon(Icons.pause),
                    label: Text(L10n.of(context).commonPause),
                  ),
                  TextButton.icon(
                    onPressed: () => ref
                        .read(fontDownloadsProvider.notifier)
                        .cancelDownload(font.id),
                    icon: const Icon(Icons.cancel),
                    label: Text(L10n.of(context).commonCancel),
                  ),
                ],
              ),
            ],
          );

        case DownloadStatus.paused:
          return Row(
            children: [
              Text(
                '${L10n.of(context).fontPaused} ${(downloadState.progress * 100).toStringAsFixed(1)}%',
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => ref
                    .read(fontDownloadsProvider.notifier)
                    .resumeDownload(font),
                icon: const Icon(Icons.play_arrow),
                label: Text(L10n.of(context).commonResume),
              ),
              TextButton.icon(
                onPressed: () => ref
                    .read(fontDownloadsProvider.notifier)
                    .cancelDownload(font.id),
                icon: const Icon(Icons.cancel),
                label: Text(L10n.of(context).commonCancel),
              ),
            ],
          );

        case DownloadStatus.failed:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${L10n.of(context).commonDownloadFailed}: ${downloadState.error}',
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => ref
                    .read(fontDownloadsProvider.notifier)
                    .startDownload(font),
                icon: const Icon(Icons.refresh),
                label: Text(L10n.of(context).commonRetry),
              ),
            ],
          );

        default:
          break;
      }
    }

    return ElevatedButton.icon(
      onPressed: () =>
          ref.read(fontDownloadsProvider.notifier).startDownload(font),
      icon: const Icon(Icons.download),
      label: Text(L10n.of(context).commonDownload),
    );
  }
}
