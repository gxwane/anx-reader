import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SystemTts extends BaseTts {
  static final SystemTts _instance = SystemTts._internal();

  factory SystemTts() {
    return _instance;
  }

  SystemTts._internal();

  final FlutterTts flutterTts = FlutterTts();

  String? _currentVoiceText;
  static String? _prevVoiceText;

  bool restarting = false;
  int _speechSessionId = 0;

  late Function getHereFunction;
  late Function getNextTextFunction;
  late Function getPrevTextFunction;

  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  @override
  void updateTtsState(TtsStateEnum newState) {
    ttsStateNotifier.value = newState;
  }

  bool get isIOS => AnxPlatform.isIOS;
  bool get isAndroid => AnxPlatform.isAndroid;
  bool get isWindows => AnxPlatform.isWindows;
  bool get isWeb => kIsWeb;

  @override
  double get volume => Prefs().ttsVolume;

  @override
  set volume(double volume) {
    Prefs().ttsVolume = volume;
    restart();
  }

  @override
  double get pitch => Prefs().ttsPitch;

  @override
  set pitch(double pitch) {
    Prefs().ttsPitch = pitch;
    restart();
  }

  @override
  double get rate => Prefs().ttsRate;

  @override
  set rate(double rate) {
    Prefs().ttsRate = rate;
    restart();
  }

  @override
  bool get isPlaying => ttsStateNotifier.value == TtsStateEnum.playing;

  @override
  String? get currentVoiceText => _currentVoiceText;

  @override
  Future<void> init(Function getCurrentText, Function getNextText,
      Function getPrevText) async {
    getHereFunction = getCurrentText;
    getNextTextFunction = getNextText;
    getPrevTextFunction = getPrevText;

    await setAwaitOptions();

    if (isAndroid) {
      await getDefaultEngine();
      await getDefaultVoice();
    }

    flutterTts.setStartHandler(() async {
      updateTtsState(TtsStateEnum.playing);
      if (!isAndroid) {
        return;
      }
      _prevVoiceText = _currentVoiceText;
      _currentVoiceText = await epubPlayerKey.currentState!.ttsPrepare();

      if (_currentVoiceText?.isNotEmpty ?? false) {
        flutterTts.speak(_currentVoiceText!);
      }
    });

    flutterTts.setCompletionHandler(() async {
      if (!isAndroid) {
        return;
      }
      updateTtsState(TtsStateEnum.playing);
      if (_currentVoiceText?.isEmpty ?? true) {
        _currentVoiceText = await getNextText();
        await speak();
      } else {
        await getNextText();
      }
    });
  }

  Future<void> setAwaitOptions() async {
    await flutterTts.awaitSpeakCompletion(true);
    if (isAndroid) {
      await flutterTts.awaitSynthCompletion(true);
      await flutterTts.setQueueMode(1);
    }
  }

  Future<void> getDefaultEngine() async {
    var engine = await flutterTts.getDefaultEngine;
    if (engine != null) {}
  }

  Future<void> getDefaultVoice() async {
    var voice = await flutterTts.getDefaultVoice;
    if (voice != null) {}
  }

  /// Apply the voice by shortName
  Future<void> _applyVoice(String? voiceShortName) async {
    if (voiceShortName == null || voiceShortName.isEmpty) {
      return;
    }

    try {
      // Get all voices to find the matching one
      final voices = await flutterTts.getVoices;
      if (voices is List) {
        for (var voice in voices) {
          final map = Map<String, dynamic>.from(voice);
          if (map['name'] == voiceShortName) {
            // flutter_tts setVoice expects a Map with 'name' and 'locale'
            await flutterTts.setVoice({
              'name': map['name'],
              'locale': map['locale'],
            });
            return;
          }
        }
      }
    } catch (e) {
      // Fallback: try to set voice directly (some platforms support this)
      // Ignore errors if voice not found
    }
  }

  /// For testing a specific voice in settings (matching OnlineTts API)
  Future<void> speakWithVoice(String content, String voiceShortName) async {
    await stop();
    await flutterTts.setVolume(volume);
    await flutterTts.setSpeechRate(normalizeSystemRate(rate));
    await flutterTts.setPitch(pitch);
    await _applyVoice(voiceShortName);
    await flutterTts.speak(content);
  }

  /// Maps canonical playback rate (1.0 = 1.0x normal speed) to platform-specific flutter_tts values.
  static double normalizeSystemRate(double canonicalRate) {
    if (Platform.isWindows) {
      // Windows flutter_tts uses (rate - 0.5) * 15 for SAPI (-10 to +10).
      // At canonical 1.0x, we want SAPI 0 -> 0.5.
      return (0.5 + (canonicalRate - 1.0) * 0.35).clamp(0.0, 1.0);
    } else {
      // iOS & Android (flutter_tts internally maps 0.5 to Android 1.0f and iOS AVSpeechUtteranceDefaultSpeechRate)
      return (0.5 * canonicalRate).clamp(0.0, 1.0);
    }
  }

  @override
  Future<void> speak({String? content, bool resetLocation = true}) async {
    final session = ++_speechSessionId;
    updateTtsState(TtsStateEnum.playing);
    await setAwaitOptions();

    if (content != null) {
      _currentVoiceText = content;
    }
    if (_currentVoiceText == null) {
      // getHereFunction() is initTts() — it initialises the JS TTS position
      // but returns void. Fetch the actual first sentence via getNextTextFunction.
      if (resetLocation) {
        await getHereFunction();
        if (session != _speechSessionId || !isPlaying) return;
      }
      _currentVoiceText = await getNextTextFunction();
    }

    if (isAndroid) {
      if (_currentVoiceText == null || _currentVoiceText!.trim().isEmpty) return;
      await flutterTts.setVolume(volume);
      await flutterTts.setSpeechRate(normalizeSystemRate(rate));
      await flutterTts.setPitch(pitch);
      try {
        final selectedVoice = SystemTtsProvider().resolveVoice(null);
        await _applyVoice(selectedVoice);
      } catch (_) {}
      await flutterTts.speak(_currentVoiceText!);
      return;
    }

    // On non-Android (Windows, macOS, iOS), drive continuous playback via loop
    while (session == _speechSessionId && isPlaying) {
      if (_currentVoiceText == null || _currentVoiceText!.trim().isEmpty) {
        // Try skipping blank line or image container
        _currentVoiceText = await getNextTextFunction();
        if (session != _speechSessionId || !isPlaying) break;
        if (_currentVoiceText == null || _currentVoiceText!.trim().isEmpty) {
          // End of section/book reached
          break;
        }
      }

      await flutterTts.setVolume(volume);
      await flutterTts.setSpeechRate(normalizeSystemRate(rate));
      await flutterTts.setPitch(pitch);

      try {
        final selectedVoice = SystemTtsProvider().resolveVoice(null);
        await _applyVoice(selectedVoice);
      } catch (_) {
        // Default system voice is used if none is explicitly configured
      }

      if (session != _speechSessionId || !isPlaying) break;

      try {
        await _speakWithWatchdog(_currentVoiceText!);
      } catch (e) {
        AnxLog.severe('SystemTts: speak error: $e');
      }

      if (session != _speechSessionId || !isPlaying) break;

      _currentVoiceText = await getNextTextFunction();
    }
  }

  /// Speaks text with a dynamic watchdog timer that guards against platform deadlocks.
  Future<dynamic> _speakWithWatchdog(String text) async {
    final completer = Completer<dynamic>();
    final timeoutMs = math.max(15000, text.length * 500);
    Timer? watchdogTimer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted && isPlaying) {
        AnxLog.warning(
            'SystemTts: speech completion timed out after ${timeoutMs}ms, forcing advance');
        flutterTts.stop();
        completer.complete(0);
      }
    });

    flutterTts.speak(text).then((res) {
      if (!completer.isCompleted) {
        completer.complete(res);
      }
    }).catchError((err) {
      if (!completer.isCompleted) {
        completer.completeError(err);
      }
    }).whenComplete(() {
      watchdogTimer.cancel();
    });

    return completer.future;
  }

  @override
  Future<dynamic> stop() async {
    _speechSessionId++;
    updateTtsState(TtsStateEnum.stopped);
    final result = await flutterTts.stop();
    _currentVoiceText = null;
    return result;
  }

  @override
  Future<void> pause() async {
    _speechSessionId++;
    updateTtsState(TtsStateEnum.paused);
    await flutterTts.stop();
  }

  @override
  Future<void> resume() async {
    if (isAndroid) {
      speak(content: _prevVoiceText);
      return;
    }
    speak(content: _currentVoiceText);
  }

  @override
  Future<void> prev() async {
    if (restarting) {
      return;
    }
    restarting = true;
    _speechSessionId++;
    await stop();
    _currentVoiceText = await getPrevTextFunction();
    speak();
    restarting = false;
  }

  @override
  Future<void> next() async {
    if (restarting) {
      return;
    }
    restarting = true;
    _speechSessionId++;
    await stop();
    _currentVoiceText = await getNextTextFunction();
    speak();
    restarting = false;
  }

  @override
  Future<void> restart() async {
    if (restarting) {
      return;
    }
    restarting = true;
    _speechSessionId++;
    final textToResume = _currentVoiceText;
    await stop();
    if (textToResume != null && textToResume.trim().isNotEmpty) {
      speak(content: textToResume, resetLocation: false);
    } else {
      speak(resetLocation: false);
    }
    restarting = false;
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    try {
      dynamic voices = await flutterTts.getVoices;
      if (voices is List) {
        return voices.map((e) {
          final map = Map<String, dynamic>.from(e);
          return TtsVoice(
              shortName: map['name'] ?? '',
              name: map['name'] ?? '',
              locale: map['locale']?.replaceAll('_', '-') ?? '',
              gender: map['gender']?.toString().toLowerCase() ?? '',
              rawData: map);
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    await flutterTts.stop();
  }
}
