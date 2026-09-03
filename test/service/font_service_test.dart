import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/service/font/font_service.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FontService Asset Management & Resilience', () {
    late Directory fontDir;
    late File sampleOtf;
    late File dummyTxt;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      fontDir = getFontDir();
      if (!await fontDir.exists()) {
        await fontDir.create(recursive: true);
      }

      // Copy test font to fontDir
      final bundledOtf = File('assets/fonts/SourceHanSerifSC-Regular.otf');
      sampleOtf = File('${fontDir.path}/TestSampleFont.otf');
      if (await bundledOtf.exists()) {
        await bundledOtf.copy(sampleOtf.path);
      }

      dummyTxt = File('${fontDir.path}/ignore_me.txt');
      await dummyTxt.writeAsString('should be ignored by font scanner');
    });

    tearDown(() async {
      if (await sampleOtf.exists()) {
        await sampleOtf.delete();
      }
      if (await dummyTxt.exists()) {
        await dummyTxt.delete();
      }
    });

    test('scanLocalFonts finds valid fonts, extracts metadata, and ignores non-font files', () async {
      final fonts = await FontService.instance.scanLocalFonts();

      expect(fonts, isNotEmpty);
      final foundSample = fonts.firstWhere(
        (f) => f.path == 'TestSampleFont.otf',
        orElse: () => throw Exception('Sample font not found'),
      );

      expect(foundSample.id, startsWith('postscript:'));
      expect(foundSample.id, contains('SourceHanSerifCN-Regular'));
      expect(foundSample.source, FontSource.localCustom);
      expect(foundSample.isDeletable, isTrue);

      // Verify dummyTxt was ignored
      final foundTxt = fonts.where((f) => f.path.endsWith('.txt'));
      expect(foundTxt, isEmpty);
    });

    test('deleteFont safely rejects non-deletable fonts and bundled fonts', () async {
      final bookPreset = FontModel.book();
      final deleted = await FontService.instance.deleteFont(bookPreset);
      expect(deleted, isFalse);

      final systemPreset = FontModel.systemUi();
      final systemDeleted = await FontService.instance.deleteFont(systemPreset);
      expect(systemDeleted, isFalse);

      // Bundled font file must be rejected from deletion
      final bundledModel = FontModel.bundled(
        label: 'Source Han Serif',
        name: 'SourceHanSerif',
        path: 'SourceHanSerifSC-Regular.otf',
        postscriptName: 'SourceHanSerifCN-Regular',
      );
      final bundledDeleted = await FontService.instance.deleteFont(bundledModel);
      expect(bundledDeleted, isFalse);
    });

    test('deleteFont removes physical file for valid custom font', () async {
      final fonts = await FontService.instance.scanLocalFonts();
      final sample = fonts.firstWhere((f) => f.path == 'TestSampleFont.otf');

      expect(await sampleOtf.exists(), isTrue);
      final success = await FontService.instance.deleteFont(sample);
      expect(success, isTrue);
      expect(await sampleOtf.exists(), isFalse);
    });
  });
}
