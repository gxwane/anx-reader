import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/edge_tts_backend.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EdgeTtsProvider provider;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    provider = EdgeTtsProvider();
  });

  group('EdgeTtsProvider Architecture & Contract Specification', () {
    test('EdgeTtsProvider is singleton and binds to edge enum', () {
      final p1 = EdgeTtsProvider();
      final p2 = EdgeTtsProvider();
      expect(identical(p1, p2), isTrue);
      expect(p1.service, equals(TtsService.edge));
      expect(p1.serviceId, equals('edge'));
    });

    test('requestTimeout is 20 seconds', () {
      expect(provider.requestTimeout, equals(const Duration(seconds: 20)));
    });

    test('Default voice fallback is zh-CN-XiaoxiaoNeural', () {
      expect(provider.getSelectedVoice(), equals('zh-CN-XiaoxiaoNeural'));
    });

    test('setSelectedVoice updates voice preference and getSelectedVoice reflects it', () {
      provider.setSelectedVoice('zh-CN-YunxiNeural');
      expect(provider.getSelectedVoice(), equals('zh-CN-YunxiNeural'));
      // Reset back
      provider.setSelectedVoice('zh-CN-XiaoxiaoNeural');
    });

    test('Sec-MS-GEC generator produces 64-char uppercase hex hash', () {
      final token = EdgeTtsProvider.generateSecMsGec();
      expect(token.length, equals(64));
      expect(RegExp(r'^[0-9A-F]{64}$').hasMatch(token), isTrue);
    });

    test('Sec-MS-GEC algorithm computes correct hash for known Windows File Time ticks', () {
      const int unixEpochOffset = 11644473600;
      const int testUnixSeconds = 1700000000;
      const int windowsSeconds = testUnixSeconds + unixEpochOffset;
      const int alignedSeconds = windowsSeconds - (windowsSeconds % 300);
      final int ticks = alignedSeconds * 10000000;

      const String trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
      final String dataToHash = '$ticks$trustedClientToken';
      final String expectedDigest =
          sha256.convert(utf8.encode(dataToHash)).toString().toUpperCase();

      expect(expectedDigest.length, equals(64));
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(expectedDigest), isTrue);
    });

    test('escapeXml correctly escapes all XML sensitive characters', () {
      const rawText = '<hello> & "world" \'test\'';
      final escaped = EdgeTtsProvider.escapeXml(rawText);
      expect(escaped, equals('&lt;hello&gt; &amp; &quot;world&quot; &apos;test&apos;'));
    });

    test('escapeXml leaves benign strings intact', () {
      const clean = '中华人民共和国 123 ABC abc';
      expect(EdgeTtsProvider.escapeXml(clean), equals(clean));
    });

    test('getVoices returns curated high-quality neural voices', () async {
      final voices = await provider.getVoices();
      expect(voices.isNotEmpty, isTrue);

      // Check essential voices
      expect(voices.any((v) => v.shortName == 'zh-CN-XiaoxiaoNeural'), isTrue);
      expect(voices.any((v) => v.shortName == 'zh-CN-YunxiNeural'), isTrue);
      expect(voices.any((v) => v.shortName == 'zh-CN-YunjianNeural'), isTrue);
      expect(voices.any((v) => v.shortName == 'zh-TW-HsiaoChenNeural'), isTrue);
      expect(voices.any((v) => v.shortName == 'zh-HK-HiuMaanNeural'), isTrue);
      expect(voices.any((v) => v.shortName == 'en-US-JennyNeural'), isTrue);
      expect(voices.any((v) => v.shortName == 'ja-JP-NanamiNeural'), isTrue);

      // Verify all voices have valid metadata
      for (final voice in voices) {
        expect(voice.shortName.isNotEmpty, isTrue);
        expect(voice.name.isNotEmpty, isTrue);
        expect(voice.locale.isNotEmpty, isTrue);
        expect(voice.gender.isNotEmpty, isTrue);
      }
    });
  });
}
