import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/service/font/system_font_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FontManagerModal extends ConsumerStatefulWidget {
  const FontManagerModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FontManagerModal(),
    );
  }

  @override
  ConsumerState<FontManagerModal> createState() => _FontManagerModalState();
}

class _FontManagerModalState extends ConsumerState<FontManagerModal> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _allSystemFonts = [];
  bool _isLoading = true;
  String _filterQuery = '';

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

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle & Title
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.font_download_outlined),
                    const SizedBox(width: 8),
                    Text(
                      L10n.of(context).font,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Import local font button
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: L10n.of(context).addNewFont,
                      onPressed: () async {
                        await ref.read(fontListProvider.notifier).importFonts();
                      },
                    ),
                    // Download fonts button
                    IconButton(
                      icon: const Icon(Icons.cloud_download_outlined),
                      tooltip: L10n.of(context).downloadFonts,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FontsSettingPage(initialTabIndex: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Search input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) => setState(() => _filterQuery = val.trim()),
                ),
              ),
              const Divider(height: 16),
              // Font list
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
                            controller: scrollController,
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
                                    fontWeight: isPinned ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  '永和九年，歲在癸丑，暮春之初 The quick brown fox',
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
          ),
        );
      },
    );
  }
}
