import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/models/font_source_model.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/providers/fonts.dart';
import 'package:anx_reader/service/font/system_font_service.dart';
import 'package:anx_reader/widgets/common/app_scrollbar.dart';
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

class _MyFontsTabState extends ConsumerState<_MyFontsTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final fontListAsync = ref.watch(fontListProvider);

    return fontListAsync.when(
      data: (fonts) {
        final activeFont = Prefs().font;

        return AppScrollbar(
          controller: _scrollController,
          child: ListView(
            controller: _scrollController,
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
        ),
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
  final ScrollController _scrollController = ScrollController();
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
    _scrollController.dispose();
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
                  : AppScrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemExtent: 72.0,
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
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
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
    final activeSource = ref.watch(activeFontSourceProvider);
    final isOfflineCache = ref.watch(onlineFontsIsCacheProvider);
    final fontList = ref.watch(fontsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Row(
            children: [
              Expanded(
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.trim());
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                onPressed: () => _showFontSourcesDialog(context),
                icon: const Icon(Icons.cloud_queue, size: 18),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text(
                        activeSource.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isOfflineCache)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .error
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    L10n.of(context).fontSourceOfflineNotice,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: fontList.when(
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

              if (filteredFonts.isEmpty) {
                return Center(
                  child: Text(
                    L10n.of(context).fontNoMatchingFonts,
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                );
              }

              return AppScrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredFonts.length,
                  itemBuilder: (context, index) {
                  final font = filteredFonts[index];
                  final sizeStr = _formatFileSize(font.size);
                  final previewUrl = resolveFontFileUrl(
                      activeSource.manifestUrl, font.preview);
                  return FilledContainer(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (font.preview.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: previewUrl,
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
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                font.desc,
                                style: TextStyle(
                                    color: Theme.of(context).hintColor),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () =>
                                          launchUrlString(font.license.url),
                                      child: Text(
                                        'License: ${font.license.name}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .hintColor,
                                          decoration:
                                              TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () =>
                                        launchUrlString(font.official),
                                    child: Text(
                                      'Official',
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
            );
          },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      L10n.of(context).fontFailedToLoadFonts,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text(L10n.of(context).commonRetry),
                          onPressed: () => ref.refresh(fontsProvider),
                        ),
                        if (!activeSource.isOfficial)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.storefront_outlined),
                            label: Text(
                                L10n.of(context).fontSourceSwitchOfficial),
                            onPressed: () {
                              ref
                                  .read(activeFontSourceProvider.notifier)
                                  .state = FontSourceModel.official;
                              Prefs().activeFontSourceId =
                                  FontSourceModel.official.id;
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showFontSourcesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final sources = Prefs().fontSources;
            final activeSource = ref.watch(activeFontSourceProvider);

            return AlertDialog(
              title: Text(L10n.of(context).fontSources),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sources.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    final isSelected = source.id == activeSource.id;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 0),
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              source.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (source.isOfficial)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                L10n.of(context).fontSourceOfficial,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        source.manifestUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      trailing: !source.isOfficial
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(L10n.of(context)
                                        .fontSourceDeleteConfirm),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(L10n.of(context)
                                            .commonCancel),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(L10n.of(context)
                                            .commonConfirm),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await Prefs().removeFontSource(source.id);
                                  if (activeSource.id == source.id) {
                                    ref
                                        .read(activeFontSourceProvider
                                            .notifier)
                                        .state = FontSourceModel.official;
                                  }
                                  setDialogState(() {});
                                }
                              },
                            )
                          : null,
                      onTap: () {
                        ref
                            .read(activeFontSourceProvider.notifier)
                            .state = source;
                        Prefs().activeFontSourceId = source.id;
                        Navigator.pop(dialogContext);
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(L10n.of(context).fontSourceAdd),
                  onPressed: () {
                    _showAddFontSourceDialog(context, () {
                      setDialogState(() {});
                    });
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(L10n.of(context).commonCancel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddFontSourceDialog(
    BuildContext parentContext,
    VoidCallback onAdded,
  ) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    bool isValidating = false;
    String? errorMessage;

    showDialog(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setAddDialogState) {
            return AlertDialog(
              title: Text(L10n.of(context).fontSourceAdd),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: L10n.of(context).fontSourceName,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    decoration: InputDecoration(
                      labelText: L10n.of(context).fontSourceUrl,
                      hintText: 'https://.../fonts-manifest.json',
                      border: const OutlineInputBorder(),
                      errorText: errorMessage,
                    ),
                  ),
                  if (isValidating) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isValidating
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(L10n.of(context).commonCancel),
                ),
                ElevatedButton(
                  onPressed: isValidating
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final url = urlController.text.trim();
                          if (name.isEmpty || url.isEmpty) return;

                          setAddDialogState(() {
                            isValidating = true;
                            errorMessage = null;
                          });

                          try {
                            await validateFontSource(url);
                            final newSource = FontSourceModel(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              name: name,
                              manifestUrl: url,
                              isOfficial: false,
                            );
                            await Prefs().addOrUpdateFontSource(newSource);
                            ref
                                .read(activeFontSourceProvider.notifier)
                                .state = newSource;
                            Prefs().activeFontSourceId = newSource.id;
                            onAdded();
                            if (context.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            setAddDialogState(() {
                              isValidating = false;
                              errorMessage =
                                  L10n.of(context).fontSourceInvalid;
                            });
                          }
                        },
                  child: Text(L10n.of(context).commonConfirm),
                ),
              ],
            );
          },
        );
      },
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
