import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/service/font/font_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'font_list.g.dart';

@Riverpod(keepAlive: true)
class FontList extends _$FontList {
  @override
  Future<List<FontModel>> build() async {
    return await loadFonts();
  }

  Future<List<FontModel>> loadFonts() async {
    final context = navigatorKey.currentContext;
    final systemFontLabel = context != null
        ? L10n.of(context).systemFont
        : 'System Font';
    final followBookLabel = context != null
        ? L10n.of(context).followBook
        : 'Follow Book';

    final localFonts = await FontService.instance.scanLocalFonts();

    // Load user pinned system fonts
    final pinnedNames = Prefs().pinnedSystemFonts;
    final pinnedSystemFonts = pinnedNames
        .map((name) => FontModel.systemFont(familyName: name))
        .toList();

    return [
      FontModel.book(label: followBookLabel),
      FontModel.systemUi(label: systemFontLabel),
      ...pinnedSystemFonts,
      ...localFonts,
    ];
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => loadFonts());
  }

  Future<void> togglePinSystemFont(String fontName) async {
    final current = List<String>.from(Prefs().pinnedSystemFonts);
    if (current.contains(fontName)) {
      current.remove(fontName);
      try {
        if (Prefs().font.id == 'system:$fontName') {
          Prefs().font = FontModel.book();
        }
      } catch (_) {
        // Guard against uninitialized preferences in tests
      }
    } else {
      current.add(fontName);
    }
    Prefs().pinnedSystemFonts = current;
    await refresh();
  }
}
