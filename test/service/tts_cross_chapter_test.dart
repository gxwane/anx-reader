import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:audio_service/audio_service.dart';
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
      'ttsRate': 1.0,
      'allowMixWithOtherAudio': false,
      'ttsService': 'edge',
    });
    await Prefs().initPrefs();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (MethodCall call) async {
      methodCalls.add(call);
      return 1;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'),
            (MethodCall call) async {
      return 1;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global'),
            (MethodCall call) async {
      return 1;
    });
  });

  setUp(() {
    methodCalls.clear();
    OnlineTts().resetForTest();
  });

  group('TTS Cross-Chapter & End-of-Book Lifecycle Tests', () {
    test('TtsHandler.updateMediaItemChapter updates mediaItem dynamically', () {
      final handler = TtsHandler();
      final initialItem = const MediaItem(
        id: 'Chapter 1',
        title: 'Chapter 1',
        album: 'Test Book',
      );
      handler.mediaItem.add(initialItem);
      handler.queue.add([initialItem]);

      // Update to Chapter 2
      handler.updateMediaItemChapter('Chapter 2');
      expect(handler.mediaItem.value?.title, equals('Chapter 2'));
      expect(handler.queue.value.first.title, equals('Chapter 2'));

      // Updating with same title should be a no-op
      handler.updateMediaItemChapter('Chapter 2');
      expect(handler.mediaItem.value?.title, equals('Chapter 2'));

      // Empty title should be ignored
      handler.updateMediaItemChapter('');
      expect(handler.mediaItem.value?.title, equals('Chapter 2'));
    });

    test('SystemTts transitions to stopped state when end of book is reached',
        () async {
      final tts = SystemTts();
      int callCount = 0;

      await tts.init(
        () async {},
        () async {
          callCount++;
          // First sentence, then empty string indicating end of book
          if (callCount == 1) return 'Final Sentence';
          return '';
        },
        () async => '',
      );

      await tts.speak(content: 'Final Sentence');

      // Once all sentences finish and empty string is returned, state should be stopped
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(tts.isPlaying, isFalse);
    });

    test('OnlineTts advanceReaderPosition stops when end of book is reached',
        () async {
      final tts = OnlineTts();

      await tts.init(
        () async => '',
        () async => '', // End of book: returns empty string
        () async => '',
      );

      tts.updateTtsState(TtsStateEnum.playing);
      final result = await tts.advanceReaderPositionForTest(tts.sessionEpoch);

      expect(result, isFalse);
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(tts.isPlaying, isFalse);
    });

    test('OnlineTts advanceReaderPosition continues when next chapter text exists',
        () async {
      final tts = OnlineTts();

      await tts.init(
        () async => '',
        () async => 'Chapter 2 opening sentence',
        () async => '',
      );

      tts.updateTtsState(TtsStateEnum.playing);
      final result = await tts.advanceReaderPositionForTest(tts.sessionEpoch);

      expect(result, isTrue);
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.playing));
      expect(tts.isPlaying, isTrue);
    });
  });
}
