import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/font/font_service.dart';
import 'package:anx_reader/utils/toast/common.dart';

Future<void> importFont() async {
  final count = await FontService.instance.importFonts();
  if (count > 0) {
    if (navigatorKey.currentContext != null) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!).commonSuccess);
    }
  }
}
