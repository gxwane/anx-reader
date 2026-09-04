import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/self_hosted_tts_backend.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _TestMockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request) handler;
  _TestMockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => handler(request);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SelfHostedTtsProvider provider;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    provider = SelfHostedTtsProvider();
  });

  tearDown(() {
    provider.httpClientOverride = null;
  });

  group('SelfHostedTtsProvider Architecture & Contract Specification', () {
    test('SelfHostedTtsProvider is singleton and binds to selfHosted enum', () {
      final p1 = SelfHostedTtsProvider();
      final p2 = SelfHostedTtsProvider();
      expect(identical(p1, p2), isTrue);
      expect(p1.service, equals(TtsService.selfHosted));
      expect(p1.serviceId, equals('selfHosted'));
    });

    test('requestTimeout is 30 seconds for local model inference', () {
      expect(provider.requestTimeout, equals(const Duration(seconds: 30)));
    });

    test('Default config provides fallback parameters', () {
      final config = provider.getConfig();
      expect(config['url'], contains('/v1/audio/speech'));
      expect(config['key'], equals(''));
      expect(config['model'], equals('tts-1'));
      expect(config['voice'], equals('default'));
    });

    test('speak omits Authorization header when key is blank or empty', () async {
      http.BaseRequest? capturedRequest;
      String? capturedBody;

      provider.saveConfig({
        'url': 'http://127.0.0.1:8000/v1/audio/speech',
        'key': '', // Blank key
        'model': 'cosyvoice-300m',
        'voice': 'speaker_01',
        'instructions': '',
      });

      provider.httpClientOverride = _TestMockClient((request) async {
        capturedRequest = request;
        if (request is http.Request) {
          capturedBody = request.body;
        }
        final dummyAudio = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00]); // MP3 frame sync
        return http.StreamedResponse(
          Stream.value(dummyAudio),
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      });

      final result = await provider.speak('你好，世界', 'speaker_01', 1.0, 1.0);
      expect(result.length, equals(4));
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers.containsKey('Authorization'), isFalse);
      expect(capturedRequest!.headers['Content-Type'], equals('application/json'));

      final json = jsonDecode(capturedBody!);
      expect(json['input'], equals('你好，世界'));
      expect(json['model'], equals('cosyvoice-300m'));
      expect(json['voice'], equals('speaker_01'));
      expect(json['response_format'], equals('mp3'));
    });

    test('speak includes Authorization Bearer header when key is provided', () async {
      http.BaseRequest? capturedRequest;

      provider.saveConfig({
        'url': 'http://192.168.1.50:8000/v1/audio/speech',
        'key': 'sk-secret-local-token',
        'model': 'chattts',
        'voice': 'default',
        'instructions': '',
      });

      provider.httpClientOverride = _TestMockClient((request) async {
        capturedRequest = request;
        final dummyAudio = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]); // WAV RIFF
        return http.StreamedResponse(
          Stream.value(dummyAudio),
          200,
          headers: {'content-type': 'audio/wav'},
        );
      });

      final result = await provider.speak('Hello world', 'default', 1.25, 1.0);
      expect(result.length, equals(4));
      expect(capturedRequest!.headers['Authorization'], equals('Bearer sk-secret-local-token'));
    });

    test('speak throws on non-audio JSON error response', () async {
      provider.saveConfig({
        'url': 'http://127.0.0.1:8000/v1/audio/speech',
        'key': '',
        'model': 'tts-1',
        'voice': 'default',
      });

      provider.httpClientOverride = _TestMockClient((request) async {
        final errorJson = utf8.encode(jsonEncode({'error': {'message': 'CUDA out of memory'}}));
        return http.StreamedResponse(
          Stream.value(errorJson),
          200, // HTTP 200 with error JSON body
        );
      });

      expect(
        provider.speak('Test', 'default', 1.0, 1.0),
        throwsA(predicate((e) =>
            e.toString().contains('CUDA out of memory') ||
            e.toString().contains('non-audio'))),
      );
    });

    test('speak throws on HTML gateway error response', () async {
      provider.saveConfig({
        'url': 'http://127.0.0.1:8000/v1/audio/speech',
        'key': '',
        'model': 'tts-1',
        'voice': 'default',
      });

      provider.httpClientOverride = _TestMockClient((request) async {
        final htmlBody = utf8.encode('<html><body>502 Bad Gateway</body></html>');
        return http.StreamedResponse(
          Stream.value(htmlBody),
          200,
        );
      });

      expect(
        provider.speak('Test', 'default', 1.0, 1.0),
        throwsA(predicate((e) => e.toString().contains('non-audio'))),
      );
    });

    test('getVoices parses voices from /audio/voices or /models endpoints', () async {
      provider.saveConfig({
        'url': 'http://127.0.0.1:8000/v1/audio/speech',
        'key': '',
      });

      provider.httpClientOverride = _TestMockClient((request) async {
        if (request.url.path.endsWith('/audio/voices')) {
          final body = jsonEncode({
            'voices': [
              {'id': 'cosy-zh-1', 'name': 'CosyVoice 晓晓', 'locale': 'zh-CN', 'gender': 'Female'},
              {'id': 'cosy-en-1', 'name': 'CosyVoice John', 'locale': 'en-US', 'gender': 'Male'},
            ]
          });
          return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
        }
        return http.StreamedResponse(Stream.value([]), 404);
      });

      final voices = await provider.getVoices();
      expect(voices.length, equals(2));
      expect(voices[0].shortName, equals('cosy-zh-1'));
      expect(voices[0].name, equals('CosyVoice 晓晓'));
      expect(voices[1].shortName, equals('cosy-en-1'));
      expect(voices[1].locale, equals('en-US'));
    });

    test('getVoices falls back gracefully when server returns 404', () async {
      provider.saveConfig({
        'url': 'http://127.0.0.1:8000/v1/audio/speech',
        'voice': 'custom_speaker',
        'key': '',
      });

      provider.httpClientOverride = _TestMockClient((request) async {
        return http.StreamedResponse(Stream.value([]), 404);
      });

      final voices = await provider.getVoices();
      expect(voices.isNotEmpty, isTrue);
      expect(voices.any((v) => v.shortName == 'custom_speaker'), isTrue);
      expect(voices.any((v) => v.shortName == 'default'), isTrue);
    });
  });
}
