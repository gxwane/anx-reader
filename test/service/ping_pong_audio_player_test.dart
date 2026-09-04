import 'package:anx_reader/service/tts/ping_pong_audio_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio MIME-Type Magic Bytes Detection Tests', () {
    test('detects RIFF WAVE header as audio/wav', () {
      final wavHeader = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // Size
        0x57, 0x41, 0x56, 0x45, // WAVE
        0x66, 0x6D, 0x74, 0x20, // fmt
      ]);
      expect(detectAudioMimeType(wavHeader), equals('audio/wav'));
    });

    test('detects OggS header as audio/ogg', () {
      final oggHeader = Uint8List.fromList([
        0x4F, 0x67, 0x67, 0x53, // OggS
        0x00, 0x02, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);
      expect(detectAudioMimeType(oggHeader), equals('audio/ogg'));
    });

    test('detects ID3 container as audio/mp3', () {
      final id3Header = Uint8List.fromList([
        0x49, 0x44, 0x33, // ID3
        0x04, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00,
      ]);
      expect(detectAudioMimeType(id3Header), equals('audio/mp3'));
    });

    test('detects raw MP3 frame sync as audio/mp3', () {
      final mp3Header = Uint8List.fromList([
        0xFF, 0xFB, // Frame sync (11 bits 1s)
        0x90, 0x64,
      ]);
      expect(detectAudioMimeType(mp3Header), equals('audio/mp3'));
    });

    test('falls back gracefully to audio/mp3 on unknown binary', () {
      final unknownHeader = Uint8List.fromList([
        0x00, 0x01, 0x02, 0x03,
      ]);
      expect(detectAudioMimeType(unknownHeader), equals('audio/mp3'));
    });
  });

  group('PingPongAudioPlayer Engine Lifecycle & Concurrency Tests', () {
    final List<MethodCall> methodCalls = [];

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'),
              (MethodCall call) async {
        methodCalls.add(call);
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
    });

    test('ensureInitialized creates player instances and sets initial state',
        () async {
      final player = PingPongAudioPlayer();
      expect(player.isInitialized, isFalse);

      await player.ensureInitialized(volume: 0.7);
      expect(player.isInitialized, isTrue);
      expect(player.activeIndex, equals(0));

      await player.dispose();
      expect(player.isInitialized, isFalse);
    });

    test(
        'C-01 Regression Guard: dispose followed by re-ensureInitialized works without throwing closed StreamController error',
        () async {
      final player = PingPongAudioPlayer();

      // First lifecycle
      await player.ensureInitialized();
      expect(player.isInitialized, isTrue);

      await player.dispose();
      expect(player.isInitialized, isFalse);

      // Re-initialization (Engine switch scenario)
      await player.ensureInitialized();
      expect(player.isInitialized, isTrue);

      // Verify stream is active and can listen
      bool eventReceived = false;
      final sub = player.onActivePlayerComplete.listen((_) {
        eventReceived = true;
      });

      expect(eventReceived, isFalse);
      await sub.cancel();
      await player.dispose();
    });

    test('advanceToNext alternates player index between 0 and 1', () async {
      final player = PingPongAudioPlayer();
      await player.ensureInitialized();

      expect(player.activeIndex, equals(0));

      final nextIndex1 = await player.advanceToNext();
      expect(nextIndex1, equals(1));
      expect(player.activeIndex, equals(1));

      final nextIndex2 = await player.advanceToNext();
      expect(nextIndex2, equals(0));
      expect(player.activeIndex, equals(0));

      await player.dispose();
    });

    test('cancelPrewarm clears prewarmed state cleanly', () async {
      final player = PingPongAudioPlayer();
      await player.ensureInitialized();

      await player.cancelPrewarm();
      expect(player.activeIndex, equals(0));

      await player.dispose();
    });
  });
}
