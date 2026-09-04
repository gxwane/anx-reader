import 'package:anx_reader/providers/fonts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveFontFileUrl Tests', () {
    test('resolves relative path with root manifest', () {
      final url = resolveFontFileUrl(
        'https://fonts.anxcye.com/fonts-manifest.json',
        'atkinson/AtkinsonHyperlegibleNext-Regular.ttf',
      );
      expect(url,
          'https://fonts.anxcye.com/atkinson/AtkinsonHyperlegibleNext-Regular.ttf');
    });

    test('resolves relative path with subdirectory manifest', () {
      final url = resolveFontFileUrl(
        'https://myrepo.org/fonts/v1/manifest.json',
        'files/serif.ttf',
      );
      expect(url, 'https://myrepo.org/fonts/v1/files/serif.ttf');
    });

    test('preserves absolute http and https urls', () {
      final httpUrl = resolveFontFileUrl(
        'https://fonts.anxcye.com/fonts-manifest.json',
        'http://cdn.example.com/font.ttf',
      );
      expect(httpUrl, 'http://cdn.example.com/font.ttf');

      final httpsUrl = resolveFontFileUrl(
        'https://fonts.anxcye.com/fonts-manifest.json',
        'https://cdn.example.com/font.ttf',
      );
      expect(httpsUrl, 'https://cdn.example.com/font.ttf');
    });

    test('resolves root-relative path correctly', () {
      final url = resolveFontFileUrl(
        'https://myrepo.org/subpath/manifest.json',
        '/global/font.ttf',
      );
      expect(url, 'https://myrepo.org/global/font.ttf');
    });
  });
}
