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

    return [
      FontModel.book(label: followBookLabel),
      FontModel.systemUi(label: systemFontLabel),
      ...localFonts,
    ];
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => loadFonts());
  }
}
