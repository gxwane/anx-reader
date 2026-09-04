import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> methodCalls = [];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'ttsVolume': 1.0,
      'ttsPitch': 1.0,
      'ttsRate': 0.5,
    });
    await Prefs().initPrefs();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (MethodCall call) async {
      methodCalls.add(call);
      switch (call.method) {
        case 'awaitSpeakCompletion':
        case 'setVolume':
        case 'setPitch':
        case 'setSpeechRate':
        case 'speak':
        case 'stop':
        case 'pause':
          return 1;
        case 'getVoices':
          return [
            {'name': 'Test Voice', 'locale': 'zh-CN'},
          ];
        default:
          return null;
      }
    });
  });

  setUp(() {
    methodCalls.clear();
  });

  group('SystemTts Specification & Platform Channel Interaction', () {
    test('SystemTts singleton instance preserves properties', () {
      final tts1 = SystemTts();
      final tts2 = SystemTts();
      expect(identical(tts1, tts2), isTrue);
      expect(tts1.volume, equals(1.0));
      expect(tts1.pitch, equals(1.0));
      expect(tts1.rate, equals(0.5));
    });

    test('setAwaitOptions configures awaitSpeakCompletion on channel',
        () async {
      final tts = SystemTts();
      await tts.setAwaitOptions();

      expect(
        methodCalls.any((call) =>
            call.method == 'awaitSpeakCompletion' && call.arguments == true),
        isTrue,
      );
    });

    test('speakWithVoice configures volume, rate, pitch, and speaks content',
        () async {
      final tts = SystemTts();
      await tts.speakWithVoice('Hello world', 'Test Voice');

      expect(methodCalls.map((c) => c.method), containsAll([
        'stop',
        'setVolume',
        'setSpeechRate',
        'setPitch',
        'speak',
      ]));

      final speakCall =
          methodCalls.firstWhere((c) => c.method == 'speak');
      expect(speakCall.arguments, equals('Hello world'));
    });

    test('stop and pause update ttsStateNotifier and call channel stop',
        () async {
      final tts = SystemTts();
      tts.updateTtsState(TtsStateEnum.playing);
      expect(tts.isPlaying, isTrue);

      await tts.pause();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.paused));

      await tts.stop();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(tts.currentVoiceText, isNull);
    });
  });
}
