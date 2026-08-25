import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class TolerantGoldenFileComparator extends LocalFileComparator {
  final double maxDifference;

  TolerantGoldenFileComparator(super.testFile, {this.maxDifference = 0.01});

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (!result.passed && result.diffPercent <= maxDifference) {
      return true;
    }

    if (!result.passed) {
      final String error = await generateFailureOutput(result, golden, basedir);
      throw FlutterError(error);
    }
    return result.passed;
  }
}

Future<void> loadGoldenTestFonts() async {
  try {
    final fontFile = File('assets/fonts/SourceHanSerifSC-Regular.otf');
    if (fontFile.existsSync()) {
      final fontBytes = fontFile.readAsBytesSync();
      for (final family in [
        '',
        'SourceHanSerif',
        'Roboto',
        'sans-serif',
        '.SF Pro Text',
        'Segoe UI',
        'PingFang SC',
        'Microsoft YaHei',
      ]) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
        await loader.load();
      }
    }

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final candidates = [
      if (flutterRoot != null) '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      'E:/FVM/cache/versions/3.35.3/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ];
    for (final path in candidates) {
      final iconFile = File(path);
      if (iconFile.existsSync()) {
        final iconBytes = iconFile.readAsBytesSync();
        final iconLoader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(iconBytes.buffer)));
        await iconLoader.load();
        break;
      }
    }
  } catch (_) {}
}

void setupGoldenComparator(String relativeTestPath, {double tolerance = 0.05}) {
  final current = goldenFileComparator;
  Uri testUri;
  if (current is LocalFileComparator) {
    testUri = current.basedir.resolve(relativeTestPath.replaceAll(r'\', '/'));
  } else {
    testUri = Uri.file(File(relativeTestPath).absolute.path);
  }
  goldenFileComparator = TolerantGoldenFileComparator(
    testUri,
    maxDifference: tolerance,
  );
}
