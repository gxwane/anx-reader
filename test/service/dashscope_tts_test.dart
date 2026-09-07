import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/dashscope/dashscope_tts_backend.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
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

  late DashscopeTtsProvider provider;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    provider = DashscopeTtsProvider();
  });

  tearDown(() {
    provider.client = http.Client();
  });

  group('DashscopeTtsProvider Architecture & Contract Specification', () {
    test('DashscopeTtsProvider is singleton and binds to dashscope enum', () {
      final p1 = DashscopeTtsProvider();
      final p2 = DashscopeTtsProvider();
      expect(identical(p1, p2), isTrue);
      expect(p1.service, equals(TtsService.dashscope));
      expect(p1.serviceId, equals('dashscope'));
    });

    test('requestTimeout is 25 seconds for synthesis and audio download', () {
      expect(provider.requestTimeout, equals(const Duration(seconds: 25)));
    });

    test('Default config provides fallback parameters with Auto language_type', () {
      final config = provider.getConfig();
      expect(config['url'], contains('multimodal-generation/generation'));
      expect(config['key'], equals(''));
      expect(config['model'], equals('qwen3-tts-flash'));
      expect(config['voice'], equals('Cherry'));
      expect(config['language_type'], equals('Auto'));
      expect(config['instructions'], equals(''));
    });

    test('Curated voice catalog contains 20 voices with valid metadata', () async {
      final voices = await provider.getVoices();
      expect(voices.length, equals(20));

      final shortNames = voices.map((v) => v.shortName).toSet();
      expect(shortNames.contains('Cherry'), isTrue);
      expect(shortNames.contains('Serena'), isTrue);
      expect(shortNames.contains('Ethan'), isTrue);
      expect(shortNames.contains('Chelsie'), isTrue);
      expect(shortNames.contains('Momo'), isTrue);
      expect(shortNames.contains('Moon'), isTrue);
      expect(shortNames.contains('Maia'), isTrue);
      expect(shortNames.contains('Kai'), isTrue);
      expect(shortNames.contains('Vincent'), isTrue);
      expect(shortNames.contains('Bella'), isTrue);
      expect(shortNames.contains('Arthur'), isTrue);
      expect(shortNames.contains('Seren'), isTrue);
      expect(shortNames.contains('Eldric Sage'), isTrue);
      expect(shortNames.contains('Bellona'), isTrue);
      expect(shortNames.contains('Vivian'), isTrue);
      expect(shortNames.contains('Neil'), isTrue);
      expect(shortNames.contains('Jada'), isTrue);
      expect(shortNames.contains('Dylan'), isTrue);
      expect(shortNames.contains('Marcus'), isTrue);
      expect(shortNames.contains('Roy'), isTrue);

      for (var v in voices) {
        expect(v.locale, equals('zh-CN'));
        expect(v.name.isNotEmpty, isTrue);
        expect(v.gender.isNotEmpty, isTrue);
        expect(v.description.isNotEmpty, isTrue);
      }
    });

    test('Voice selection and persistence contract', () {
      provider.setSelectedVoice('Vivian');
      expect(provider.getSelectedVoice(), equals('Vivian'));

      // Revert to default
      provider.setSelectedVoice('Cherry');
      expect(provider.getSelectedVoice(), equals('Cherry'));
    });

    test('convertVoiceModel handles TtsVoice, Map, and fallbacks', () {
      const voice = TtsVoice(shortName: 'Test', name: 'TestVoice', locale: 'zh-CN');
      expect(provider.convertVoiceModel(voice), equals(voice));

      final fromMap = provider.convertVoiceModel({
        'ShortName': 'Mapped',
        'FriendlyName': 'Mapped Voice',
        'Locale': 'zh-CN',
      });
      expect(fromMap.shortName, equals('Mapped'));
      expect(fromMap.name, equals('Mapped Voice'));

      final fallback = provider.convertVoiceModel('invalid');
      expect(fallback.shortName, equals(''));
    });

    test('validateConfig rejects empty and whitespace keys, accepts valid keys', () {
      provider.saveConfig({'key': ''});
      expect(provider.validateConfig(), contains('API key'));

      provider.saveConfig({'key': '   '});
      expect(provider.validateConfig(), contains('API key'));

      provider.saveConfig({'key': 'sk-valid-key-123'});
      expect(provider.validateConfig(), isNull);
    });
  });

  group('DashscopeTtsProvider Synthesis Pipeline & Error Handling', () {
    test('speak throws if API key is missing', () async {
      provider.saveConfig({
        'key': '',
      });

      expect(
        () => provider.speak('Hello', 'Cherry', 1.0, 1.0),
        throwsA(predicate((e) => e.toString().contains('API key'))),
      );
    });

    test('speak executes 2-phase POST generation and GET audio download successfully', () async {
      http.BaseRequest? capturedPostRequest;
      String? capturedPostBody;
      http.BaseRequest? capturedGetRequest;

      final dummyMp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x64, 0x01, 0x02]);

      provider.saveConfig({
        'url': 'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
        'key': 'sk-test-valid-key-123',
        'model': 'qwen3-tts-flash',
        'voice': 'Cherry',
        'language_type': 'Auto',
        'instructions': '',
      });

      provider.client = _TestMockClient((request) async {
        if (request.method == 'POST') {
          capturedPostRequest = request;
          if (request is http.Request) {
            capturedPostBody = request.body;
          }
          final responseBody = jsonEncode({
            'output': {
              'audio': {
                'url': 'https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/audio/sample_123.mp3'
              }
            },
            'usage': {'characters': 5},
            'request_id': 'req-test-uuid'
          });
          return http.StreamedResponse(
            Stream.value(utf8.encode(responseBody)),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.method == 'GET' &&
            request.url.toString().contains('sample_123.mp3')) {
          capturedGetRequest = request;
          return http.StreamedResponse(
            Stream.value(dummyMp3),
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
        }
        return http.StreamedResponse(Stream.value([]), 404);
      });

      final result = await provider.speak('你好世界', 'Cherry', 1.0, 1.0);

      expect(result, equals(dummyMp3));
      expect(capturedPostRequest, isNotNull);
      expect(capturedPostRequest!.headers['Authorization'], equals('Bearer sk-test-valid-key-123'));
      expect(capturedPostRequest!.headers['Content-Type'], equals('application/json'));

      final jsonPayload = jsonDecode(capturedPostBody!);
      expect(jsonPayload['model'], equals('qwen3-tts-flash'));
      expect(jsonPayload['parameters']['response_format'], equals('mp3'));
      expect(jsonPayload['input']['text'], equals('你好世界'));
      expect(jsonPayload['input']['voice'], equals('Cherry'));
      expect(jsonPayload['input']['language_type'], equals('Auto'));
      expect(jsonPayload['input'].containsKey('instructions'), isFalse);

      expect(capturedGetRequest, isNotNull);
      expect(capturedGetRequest!.url.toString(), contains('sample_123.mp3'));
    });

    test('speak dynamically injects rate instructions when rate is not 1.0', () async {
      String? capturedPostBody;

      final dummyMp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00]);

      provider.saveConfig({
        'key': 'sk-test-valid-key',
        'instructions': '请使用轻松随意的语气。',
      });

      provider.client = _TestMockClient((request) async {
        if (request.method == 'POST') {
          if (request is http.Request) {
            capturedPostBody = request.body;
          }
          final responseBody = jsonEncode({
            'output': {
              'audio': {
                'url': 'https://oss.aliyun.com/audio/sample_fast.mp3'
              }
            }
          });
          return http.StreamedResponse(
            Stream.value(utf8.encode(responseBody)),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else {
          return http.StreamedResponse(Stream.value(dummyMp3), 200);
        }
      });

      await provider.speak('加速朗读测试', 'Serena', 1.25, 1.0);

      expect(capturedPostBody, isNotNull);
      final jsonPayload = jsonDecode(capturedPostBody!);
      final instructions = jsonPayload['input']['instructions'] as String;
      expect(instructions, contains('请使用轻松随意的语气。'));
      expect(instructions, contains('请以1.25倍速朗读。'));
    });

    test('speak throws structured exception on DashScope non-200 HTTP error', () async {
      provider.saveConfig({
        'key': 'sk-invalid-key',
      });

      provider.client = _TestMockClient((request) async {
        final errorJson = jsonEncode({
          'code': 'InvalidApiKey',
          'message': 'Invalid API-key provided.',
          'request_id': 'error-req-123'
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode(errorJson)),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        () => provider.speak('Test', 'Cherry', 1.0, 1.0),
        throwsA(predicate((e) =>
            e.toString().contains('401') &&
            e.toString().contains('InvalidApiKey'))),
      );
    });

    test('speak throws when DashScope response does not contain audio URL', () async {
      provider.saveConfig({
        'key': 'sk-test-key',
      });

      provider.client = _TestMockClient((request) async {
        final emptyOutputJson = jsonEncode({
          'output': {},
          'request_id': 'req-no-audio'
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode(emptyOutputJson)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        () => provider.speak('Test', 'Cherry', 1.0, 1.0),
        throwsA(predicate((e) => e.toString().contains('returned no audio url'))),
      );
    });

    test('speak throws when audio download returns HTTP non-200', () async {
      provider.saveConfig({
        'key': 'sk-test-key',
      });

      provider.client = _TestMockClient((request) async {
        if (request.method == 'POST') {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'output': {
                'audio': {'url': 'https://oss.aliyun.com/audio/missing.mp3'}
              }
            }))),
            200,
          );
        } else {
          return http.StreamedResponse(Stream.value([]), 404);
        }
      });

      expect(
        () => provider.speak('Test', 'Cherry', 1.0, 1.0),
        throwsA(predicate((e) => e.toString().contains('Failed to download DashScope audio'))),
      );
    });
  });
}
