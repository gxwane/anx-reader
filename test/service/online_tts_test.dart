import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> audioMethodCalls = [];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'ttsVolume': 0.8,
      'ttsPitch': 1.0,
      'ttsRate': 1.0,
      'ttsService': 'edge',
    });
    await Prefs().initPrefs();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'),
            (MethodCall call) async {
      audioMethodCalls.add(call);
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
    audioMethodCalls.clear();
  });

  group('OnlineTts Engine & Ping-Pong Pipeline Specification', () {
    test('OnlineTts singleton instance preserves properties', () {
      final tts1 = OnlineTts();
      final tts2 = OnlineTts();
      expect(identical(tts1, tts2), isTrue);
      expect(tts1.volume, equals(0.8));
      expect(tts1.pitch, equals(1.0));
      expect(tts1.rate, equals(1.0));
    });

    test('Property mutators update Prefs and propagate properly', () {
      final tts = OnlineTts();

      tts.volume = 0.5;
      expect(Prefs().ttsVolume, equals(0.5));
      expect(tts.volume, equals(0.5));

      tts.pitch = 1.2;
      expect(Prefs().ttsPitch, equals(1.2));
      expect(tts.pitch, equals(1.2));

      tts.rate = 1.5;
      expect(Prefs().ttsRate, equals(1.5));
      expect(tts.rate, equals(1.5));
    });

    test('updateTtsState and isPlaying toggle state reactively', () {
      final tts = OnlineTts();
      expect(tts.isPlaying, isFalse);

      tts.updateTtsState(TtsStateEnum.playing);
      expect(tts.isPlaying, isTrue);
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.playing));

      tts.updateTtsState(TtsStateEnum.paused);
      expect(tts.isPlaying, isFalse);
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.paused));

      tts.updateTtsState(TtsStateEnum.stopped);
      expect(tts.isPlaying, isFalse);
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('pause, resume, and stop transition states and control audio engine',
        () async {
      final tts = OnlineTts();

      await tts.pause();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.paused));

      await tts.resume();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.playing));

      await tts.stop();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(tts.currentVoiceText, isNull);
    });

    test('init stores navigation callbacks safely', () async {
      final tts = OnlineTts();
      bool currentCalled = false;
      bool nextCalled = false;
      bool prevCalled = false;

      await tts.init(
        () async => currentCalled = true,
        () async => nextCalled = true,
        () async => prevCalled = true,
      );

      expect(tts.isInit, isTrue);
      await tts.getHereFunction();
      expect(currentCalled, isTrue);
      await tts.getNextTextFunction();
      expect(nextCalled, isTrue);
      await tts.getPrevTextFunction();
      expect(prevCalled, isTrue);
    });

    test('speak respects resetLocation parameter to avoid jump-to-beginning',
        () async {
      final tts = OnlineTts();
      int hereCallCount = 0;

      await tts.init(
        () async => hereCallCount++,
        () async => '',
        () async => '',
      );

      // When resetLocation is false (as in next/prev/restart), getHereFunction must not be called
      unawaited(tts.speak(resetLocation: false));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(hereCallCount, equals(0));
      await tts.stop();

      // When resetLocation is true (initial play), getHereFunction is called
      unawaited(tts.speak(resetLocation: true));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(hereCallCount, equals(1));
      await tts.stop();
    });

    test(
        'next, prev, and restart invoke respective navigation without resetting location',
        () async {
      final tts = OnlineTts();
      int hereCount = 0;
      int nextCount = 0;
      int prevCount = 0;

      await tts.init(
        () async => hereCount++,
        () async => nextCount++,
        () async => prevCount++,
      );

      await tts.next();
      expect(nextCount, equals(1));
      expect(hereCount, equals(0));
      await tts.stop();

      await tts.prev();
      expect(prevCount, equals(1));
      expect(hereCount, equals(0));
      await tts.stop();

      await tts.restart();
      expect(hereCount, equals(0));
      await tts.stop();
    });

    test('pause cancels watchdog and blocks sentence advancement until resume',
        () async {
      final tts = OnlineTts();
      int nextTextCount = 0;

      await tts.init(
        () async => '',
        () async {
          nextTextCount++;
          return '';
        },
        () async => '',
      );

      // Start speaking
      unawaited(tts.speak(resetLocation: false));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(tts.isPlaying, isTrue);

      // Pause playback
      await tts.pause();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.paused));
      expect(tts.isPlaying, isFalse);

      final countAtPause = nextTextCount;

      // Simulate waiting during pause - player loop must remain blocked at pause gate
      await Future.delayed(const Duration(milliseconds: 100));
      expect(nextTextCount, equals(countAtPause));

      // Resume playback
      await tts.resume();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.playing));
      expect(tts.isPlaying, isTrue);

      await tts.stop();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('stop while paused cleanly releases pause gate without throwing',
        () async {
      final tts = OnlineTts();

      await tts.init(
        () async => '',
        () async => '',
        () async => '',
      );

      unawaited(tts.speak(resetLocation: false));
      await Future.delayed(const Duration(milliseconds: 20));

      await tts.pause();
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.paused));

      // Stop while paused must cleanly unblock pause barrier without duplicate completion
      expect(() async => await tts.stop(), returnsNormally);
      expect(tts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });
  });
}
