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
      'ttsVoiceModel_system': 'Test Voice',
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

    test('speak updates state to playing and advances through sentences',
        () async {
      final tts = SystemTts();
      final sentences = ['Sentence 2', ''];
      int nextIndex = 0;

      await tts.init(
        () async {},
        () async {
          if (nextIndex < sentences.length) {
            return sentences[nextIndex++];
          }
          return '';
        },
        () async => '',
      );

      // Speak sentence 1
      await tts.speak(content: 'Sentence 1');

      final speakCalls =
          methodCalls.where((c) => c.method == 'speak').toList();
      expect(speakCalls.length, equals(2));
      expect(speakCalls.first.arguments, equals('Sentence 1'));
      expect(speakCalls[1].arguments, equals('Sentence 2'));
      await tts.stop();
    });

    test('stop interrupts in-flight speech session epoch token', () async {
      final tts = SystemTts();
      int callCount = 0;

      await tts.init(
        () async {},
        () async {
          callCount++;
          await tts.stop(); // Intervene and stop
          return 'Should not be spoken';
        },
        () async => '',
      );

      await tts.speak(content: 'Initial sentence');

      final speakCalls =
          methodCalls.where((c) => c.method == 'speak').toList();
      expect(callCount, equals(1));
      expect(speakCalls.any((c) => c.arguments == 'Should not be spoken'), isFalse);
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('speak skips whitespace-only sentence and advances to next content',
        () async {
      final tts = SystemTts();
      final sentences = ['   ', 'Sentence 2', ''];
      int nextIndex = 0;

      await tts.init(
        () async {},
        () async {
          if (nextIndex < sentences.length) {
            return sentences[nextIndex++];
          }
          return '';
        },
        () async => '',
      );

      await tts.speak(content: 'Sentence 1');

      final speakCalls =
          methodCalls.where((c) => c.method == 'speak').toList();
      expect(speakCalls.map((c) => c.arguments),
          containsAllInOrder(['Sentence 1', 'Sentence 2']));
      expect(
          speakCalls.any((c) => (c.arguments as String).trim().isEmpty), isFalse);
      await tts.stop();
    });

    test(
        'pause immediately stops platform audio and resume reliably restarts sentence',
        () async {
      final tts = SystemTts();

      await tts.init(
        () async {},
        () async => '',
        () async => '',
      );

      // Start speaking
      await tts.speak(content: 'Test long sentence to be paused');

      // Pause while speaking
      await tts.pause();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.paused));
      expect(methodCalls.any((c) => c.method == 'stop'), isTrue);

      // Resume
      await tts.resume();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.playing));

      final speakCalls =
          methodCalls.where((c) => c.method == 'speak').toList();
      expect(speakCalls.last.arguments, equals('Test long sentence to be paused'));

      await tts.stop();
    });
  });
}
