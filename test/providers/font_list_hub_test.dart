import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    tempDir = await Directory.systemTemp.createTemp('anx_font_hub_test_');
    documentPath = tempDir.path;
    final fontDir = getFontDir();
    if (!fontDir.existsSync()) {
      fontDir.createSync(recursive: true);
    }
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FontList Notifier Encapsulation & Lifecycle', () {
    test('deleteFont safely rejects non-deletable and bundled fonts', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final bookFont = FontModel.book();
      final deleteResult = await container.read(fontListProvider.notifier).deleteFont(bookFont);
      expect(deleteResult, isFalse);

      final bundledFont = FontModel(
        id: 'postscript:Bookerly-Regular',
        label: 'Bookerly',
        name: 'Bookerly',
        path: 'Bookerly-Regular.ttf',
        source: FontSource.bundled,
        isDeletable: false,
      );
      final bundledDeleteResult = await container.read(fontListProvider.notifier).deleteFont(bundledFont);
      expect(bundledDeleteResult, isFalse);
    });

    test('deleteFont removes custom font and refreshes provider list', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Create a test font file in fontDir
      final fontDir = getFontDir();
      final testFontFile = File('${fontDir.path}${Platform.pathSeparator}TestCustom.ttf');
      await testFontFile.writeAsBytes(List.filled(200, 0));

      final customFont = FontModel(
        id: 'file:TestCustom.ttf',
        label: 'TestCustom',
        name: 'TestCustom',
        path: testFontFile.path,
        source: FontSource.localCustom,
        isDeletable: true,
      );

      expect(testFontFile.existsSync(), isTrue);

      final deleteResult = await container.read(fontListProvider.notifier).deleteFont(customFont);
      expect(deleteResult, isTrue);
      expect(testFontFile.existsSync(), isFalse);
    });
  });
}
