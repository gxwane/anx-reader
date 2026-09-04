import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/ping_pong_audio_player.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class OnlineTts extends BaseTts {
  static final OnlineTts _instance = OnlineTts._internal();

  factory OnlineTts() {
    return _instance;
  }

  OnlineTts._internal();

  // ============ Configuration ============
  static const int _bufferCapacity = 10;
  static const int _batchSize = 5; // Max concurrent fetches
  static const int _maxRetries = 2;

  // ============ Audio Engine & Concurrency ============
  final PingPongAudioPlayer _pingPongPlayer = PingPongAudioPlayer();
  StreamSubscription<int>? _playerCompleteSubscription;
  int _sessionEpoch = 0;

  // ============ Ordered Buffer ============
  // Segments are added in order; audio is fetched in background
  final List<TtsSegment> _buffer = [];
  final Set<String> _bufferKeys = {};
  TtsSegment? _currentSegment;
  String? _currentVoiceText;
  int _audioFetchVersion = 0; // Version counter for audio fetches
  // ============ Prefetcher State ============
  bool _isPrefetcherRunning = false;
  Completer<void>? _prefetcherCompleter;

  // ============ Player State ============
  bool _isPlayerRunning = false;
  Completer<void>? _playerCompleter;
  Completer<void>? _playbackCompleter;
  Timer? _playbackWatchdogTimer;
  Completer<void>? _resumeCompleter;

  // ============ Lifecycle ============
  late Function getHereFunction;
  late Function getNextTextFunction;
  late Function getPrevTextFunction;
  bool isInit = false;
  bool _shouldStop = false;
  bool _isNavigating = false;

  // ============ Backend ============
  TtsServiceProvider? _currentBackend;

  TtsServiceProvider get backend {
    TtsService service = getTtsService(Prefs().ttsService);
    if (_currentBackend?.service != service) {
      _currentBackend = service.provider;
    }
    return _currentBackend!;
  }

  // ============ TtsStateNotifier ============
  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  @override
  void updateTtsState(TtsStateEnum newState) {
    ttsStateNotifier.value = newState;
  }

  // ============ Properties ============
  @override
  double get volume => Prefs().ttsVolume;

  @override
  set volume(double volume) {
    Prefs().ttsVolume = volume;
    _pingPongPlayer.setVolume(volume);
  }

  @override
  double get pitch => Prefs().ttsPitch;

  @override
  set pitch(double pitch) {
    Prefs().ttsPitch = pitch;
    // Clear pending audio so it will be re-fetched with new pitch
    _clearPendingAudio();
  }

  @override
  set rate(double rate) {
    Prefs().ttsRate = rate;
    // Clear pending audio so it will be re-fetched with new rate
    _clearPendingAudio();
  }

  @override
  double get rate => Prefs().ttsRate;

  @override
  bool get isPlaying => ttsStateNotifier.value == TtsStateEnum.playing;

  @override
  String? get currentVoiceText => _currentVoiceText;

  @override
  Future<List<TtsVoice>> getVoices() async {
    return await backend.getVoices();
  }

  // ============ Initialization ============
  @override
  Future<void> init(Function getCurrentText, Function getNextText,
      Function getPrevText) async {
    getHereFunction = getCurrentText;
    getNextTextFunction = getNextText;
    getPrevTextFunction = getPrevText;
    isInit = true;
  }

  // ============ Audio Player Management ============
  Future<void> _ensurePlayer() async {
    await _pingPongPlayer.ensureInitialized(volume: volume);
  }

  Future<void> _disposePlayer() async {
    await _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = null;
    await _pingPongPlayer.stop();
  }

  // ============ Watchdog & Pause Barrier Helpers ============
  void _startPlaybackWatchdog(int epoch) {
    _cancelPlaybackWatchdog();
    _playbackWatchdogTimer = Timer(const Duration(seconds: 60), () {
      if (isPlaying && !_shouldStop && epoch == _sessionEpoch) {
        AnxLog.warning('OnlineTts: active playback watchdog timeout (60s)');
        if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
          _playbackCompleter!.complete();
        }
      }
    });
  }

  void _cancelPlaybackWatchdog() {
    _playbackWatchdogTimer?.cancel();
    _playbackWatchdogTimer = null;
  }

  Future<void> _waitIfPaused(int epoch) async {
    while (ttsStateNotifier.value == TtsStateEnum.paused &&
        !_shouldStop &&
        epoch == _sessionEpoch) {
      _resumeCompleter ??= Completer<void>();
      await _resumeCompleter!.future;
    }
  }

  void _releaseResumeCompleter() {
    if (_resumeCompleter != null && !_resumeCompleter!.isCompleted) {
      _resumeCompleter!.complete();
    }
    _resumeCompleter = null;
  }

  // ============ Buffer Management ============
  String _segmentKey(TtsSentence sentence) {
    if (sentence.cfi != null && sentence.cfi!.isNotEmpty) {
      return sentence.cfi!;
    }
    return '${sentence.text.hashCode}';
  }

  void _resetBuffer() {
    _buffer.clear();
    _bufferKeys.clear();
    _currentSegment = null;
    _currentVoiceText = null;
  }

  /// Clear audio for all pending segments (not currently playing)
  /// so they will be re-fetched with new settings
  void _clearPendingAudio() {
    _audioFetchVersion++; // Increment version to invalidate in-flight fetches
    unawaited(_pingPongPlayer.cancelPrewarm());
    for (final segment in _buffer) {
      // Clear audio so it will be re-fetched
      segment.audio = null;
      segment.isSilent = false;
      segment.fetchVersion = _audioFetchVersion; // Mark with current version
    }
    AnxLog.info(
        'Cleared pending audio buffer - will re-fetch with new settings (version: $_audioFetchVersion)');
  }

  // ============ Producer: Prefetcher Loop ============
  Future<void> _startPrefetcher(int epoch) async {
    if (_isPrefetcherRunning) return;
    _isPrefetcherRunning = true;
    _prefetcherCompleter = Completer<void>();

    try {
      while (!_shouldStop && epoch == _sessionEpoch) {
        // Check for segments that need audio re-fetch (after settings change)
        final segmentsNeedingAudio =
            _buffer.where((s) => !s.isReady && !s.isSilent).toList();

        if (segmentsNeedingAudio.isNotEmpty) {
          // Re-fetch audio for segments that were cleared
          for (var i = 0; i < segmentsNeedingAudio.length; i += _batchSize) {
            if (_shouldStop || epoch != _sessionEpoch) break;
            final batch =
                segmentsNeedingAudio.skip(i).take(_batchSize).toList();
            final futures =
                batch.map((segment) => _fetchAudioForSegment(segment, epoch));
            await Future.wait(futures);
          }
        }

        final neededCount = _bufferCapacity - _buffer.length;

        if (neededCount <= 0) {
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }

        // Collect sentences from the reader
        final sentences = await _collectSentences(neededCount);

        if (sentences.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }

        // Create placeholder segments in ORDER first
        final newSegments = <TtsSegment>[];
        for (final sentence in sentences) {
          if (_shouldStop || epoch != _sessionEpoch) break;
          final key = _segmentKey(sentence);
          if (_bufferKeys.contains(key)) continue;

          _bufferKeys.add(key);
          final segment = TtsSegment(sentence: sentence);
          newSegments.add(segment);
          _buffer.add(segment); // Add in order!
        }

        // Now fetch audio in batches to limit concurrency
        for (var i = 0; i < newSegments.length; i += _batchSize) {
          if (_shouldStop || epoch != _sessionEpoch) break;
          final batch = newSegments.skip(i).take(_batchSize).toList();
          final futures =
              batch.map((segment) => _fetchAudioForSegment(segment, epoch));
          await Future.wait(futures);
        }
      }
    } catch (e) {
      AnxLog.severe('Prefetcher error: $e');
    } finally {
      _isPrefetcherRunning = false;
      _prefetcherCompleter?.complete();
      _prefetcherCompleter = null;
    }
  }

  Future<List<TtsSentence>> _collectSentences(int count) async {
    final state = epubPlayerKey.currentState;
    if (state == null) return [];

    try {
      final sentences = await state.ttsCollectDetails(
        count: count,
        includeCurrent: _buffer.isEmpty && _currentSegment == null,
      );

      // Filter out already buffered sentences
      final newSentences = <TtsSentence>[];
      for (final s in sentences) {
        final key = _segmentKey(s);
        if (!_bufferKeys.contains(key)) {
          newSentences.add(s);
        }
      }

      // Note: We do NOT call getNextTextFunction here.
      // Advancing the reader position should only happen in the player loop
      // after playback completes, to avoid interfering with highlighting.

      return newSentences;
    } catch (e) {
      AnxLog.severe('Collect sentences error: $e');
      return [];
    }
  }

  Future<void> _fetchAudioForSegment(TtsSegment segment, int epoch) async {
    if (_shouldStop || epoch != _sessionEpoch) return;
    if (segment.isReady) return;

    // Capture the version at the start of fetching
    final targetVersion = segment.fetchVersion;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (_shouldStop || epoch != _sessionEpoch) return;
      if (segment.isReady) return;

      try {
        final bytes = await backend
            .speak(
              segment.sentence.text,
              null,
              rate,
              pitch,
            )
            .timeout(backend.requestTimeout);

        if (epoch != _sessionEpoch) return;

        // Check if version is still valid (settings haven't changed during fetch)
        if (segment.fetchVersion != targetVersion) {
          AnxLog.info(
              'Audio fetch completed but version changed - discarding (segment version: ${segment.fetchVersion}, target: $targetVersion)');
          return;
        }

        if (bytes.isEmpty) {
          segment.isSilent = true;
        } else {
          segment.audio = bytes;
          // If this segment is the immediate next segment in buffer, prewarm it on the idle player
          if (_isPlayerRunning &&
              !_shouldStop &&
              _buffer.isNotEmpty &&
              identical(_buffer.first, segment)) {
            unawaited(_pingPongPlayer.prewarmNext(bytes));
          }
        }
        return; // Success, exit retry loop
      } on TimeoutException {
        if (epoch != _sessionEpoch) return;
        AnxLog.severe(
            'Fetch timeout (attempt ${attempt + 1}/$_maxRetries): "${segment.sentence.text.substring(0, segment.sentence.text.length.clamp(0, 20))}..."');
        if (attempt == _maxRetries) {
          if (segment.fetchVersion == targetVersion && epoch == _sessionEpoch) {
            segment.isSilent = true;
          }
        }
      } catch (e) {
        if (epoch != _sessionEpoch) return;
        AnxLog.severe('Fetch error (attempt ${attempt + 1}): $e');
        if (attempt == _maxRetries) {
          if (segment.fetchVersion == targetVersion && epoch == _sessionEpoch) {
            segment.isSilent = true;
          }
        }
      }
    }
  }

  // ============ Consumer: Player Loop ============
  Future<void> _startPlayer(int epoch) async {
    if (_isPlayerRunning) return;
    _isPlayerRunning = true;
    _playerCompleter = Completer<void>();

    await _ensurePlayer();
    _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription =
        _pingPongPlayer.onActivePlayerComplete.listen((_) {
      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
        _playbackCompleter!.complete();
      }
    });

    bool isFirstSegment = true;

    try {
      while (!_shouldStop && epoch == _sessionEpoch) {
        // 1. Initial pause barrier
        await _waitIfPaused(epoch);
        if (_shouldStop || epoch != _sessionEpoch) break;

        // Wait for buffer to have a segment
        while (_buffer.isEmpty && !_shouldStop && epoch == _sessionEpoch) {
          await Future.delayed(const Duration(milliseconds: 30));
        }
        if (_shouldStop || epoch != _sessionEpoch) break;

        // Get the FIRST segment (preserving order)
        final segment = _buffer.first;

        // Starvation protection: wait up to 8s for segment audio to be ready
        final waitStart = DateTime.now();
        while (!segment.isReady && !_shouldStop && epoch == _sessionEpoch) {
          if (DateTime.now().difference(waitStart).inSeconds >= 8) {
            AnxLog.warning(
                'OnlineTts: starvation timeout (8s) waiting for segment audio; marking silent');
            segment.isSilent = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 20));
        }
        if (_shouldStop || epoch != _sessionEpoch) break;

        // 2. CRITICAL GATE: Pause barrier BEFORE consuming buffer & firing hardware audio!
        await _waitIfPaused(epoch);
        if (_shouldStop || epoch != _sessionEpoch) break;

        // Remove from buffer now that it's ready to play
        _buffer.removeAt(0);
        _currentSegment = segment;
        _currentVoiceText = segment.sentence.text;

        // Visual-audio decoupling: visual highlighting is strictly an asynchronous
        // observer, never blocking the audio master clock.
        unawaited(_highlightSegment(segment));

        // Handle silent segment
        if (segment.isSilent) {
          await Future.delayed(const Duration(milliseconds: 100));
          await _waitIfPaused(epoch);
          if (!_shouldStop && epoch == _sessionEpoch) {
            unawaited(getNextTextFunction());
          }
          _currentSegment = null;
          continue;
        }

        // Set up playback completion signal
        _playbackCompleter = Completer<void>();
        _startPlaybackWatchdog(epoch);

        try {
          if (isFirstSegment) {
            await _pingPongPlayer.playActive(segment.audio!);
            isFirstSegment = false;
          } else {
            await _pingPongPlayer.advanceToNext(fallbackBytes: segment.audio);
          }
        } catch (e) {
          AnxLog.severe('OnlineTts playback error: $e');
        }

        // Proactively prewarm next segment into idle player while current is playing
        if (_buffer.isNotEmpty &&
            _buffer.first.isReady &&
            !_buffer.first.isSilent &&
            _buffer.first.audio != null) {
          unawaited(_pingPongPlayer.prewarmNext(_buffer.first.audio!));
        }

        // Wait for active player to finish current sentence (no unconstrained .timeout())
        if (_playbackCompleter != null) {
          await _playbackCompleter!.future;
        }

        _cancelPlaybackWatchdog();
        _playbackCompleter = null;
        _currentSegment = null;

        // 3. Pause barrier BEFORE advancing reader position
        await _waitIfPaused(epoch);
        if (!_shouldStop && epoch == _sessionEpoch) {
          unawaited(getNextTextFunction());
        }
      }
    } catch (e) {
      AnxLog.severe('Player loop error: $e');
    } finally {
      _cancelPlaybackWatchdog();
      _releaseResumeCompleter();
      _isPlayerRunning = false;
      _playerCompleter?.complete();
      _playerCompleter = null;
    }
  }

  Future<void> _highlightSegment(TtsSegment segment) async {
    final state = epubPlayerKey.currentState;
    final cfi = segment.sentence.cfi;
    if (state == null || cfi == null || cfi.isEmpty) return;
    try {
      await state.ttsHighlightByCfi(cfi);
    } catch (_) {}
  }

  // ============ Public API ============
  @override
  Future<void> speak({String? content, bool resetLocation = true}) async {
    final int epoch = ++_sessionEpoch;
    _shouldStop = false;
    updateTtsState(TtsStateEnum.playing);

    // Sync to current location only when starting fresh
    if (resetLocation) {
      try {
        await getHereFunction();
      } catch (_) {}
    }

    if (epoch != _sessionEpoch) return;

    // Start both loops
    unawaited(_startPrefetcher(epoch));
    await _startPlayer(epoch);
  }

  @override
  Future<void> stop() async {
    _sessionEpoch++;
    _shouldStop = true;
    _cancelPlaybackWatchdog();
    _releaseResumeCompleter();
    updateTtsState(TtsStateEnum.stopped);

    // 1. Immediately silence audio hardware (<1ms)
    await _pingPongPlayer.stop();

    // 2. Unblock player loop immediately
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }

    // 3. Gracefully wait for background loops with bounded timeout
    try {
      await Future.wait([
        if (_prefetcherCompleter != null) _prefetcherCompleter!.future,
        if (_playerCompleter != null) _playerCompleter!.future,
      ]).timeout(const Duration(milliseconds: 300));
    } catch (_) {}

    // 4. Cleanup and reset
    await _disposePlayer();
    _resetBuffer();
  }

  @override
  Future<void> pause() async {
    _cancelPlaybackWatchdog();
    await _pingPongPlayer.pause();
    updateTtsState(TtsStateEnum.paused);
    _resumeCompleter ??= Completer<void>();
  }

  @override
  Future<void> resume() async {
    await _pingPongPlayer.resume();
    updateTtsState(TtsStateEnum.playing);
    _releaseResumeCompleter();
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _startPlaybackWatchdog(_sessionEpoch);
    }
  }

  @override
  Future<void> prev() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await stop();
      await getPrevTextFunction();
      unawaited(speak(resetLocation: false));
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Future<void> next() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      // Buffer-accelerated switch: if actively playing and next prewarmed segment is ready
      if (isPlaying && _buffer.isNotEmpty && _buffer.first.isReady) {
        _cancelPlaybackWatchdog();
        await _pingPongPlayer.activePlayer.stop();
        if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
          _playbackCompleter!.complete();
          return;
        }
      }

      // Cold fallback
      await stop();
      await getNextTextFunction();
      unawaited(speak(resetLocation: false));
    } finally {
      _isNavigating = false;
    }
  }

  @override
  Future<void> restart() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await stop();
      unawaited(speak(resetLocation: false));
    } finally {
      _isNavigating = false;
    }
  }

  /// For testing a specific voice in settings
  Future<void> speakWithVoice(String content, String voice) async {
    await stop();
    await _ensurePlayer();

    final bytes = await backend.speak(content, voice, rate, pitch);
    if (bytes.isNotEmpty) {
      await _pingPongPlayer.playActive(bytes);
    }
  }

  @override
  Future<void> dispose() async {
    _cancelPlaybackWatchdog();
    _releaseResumeCompleter();
    await stop();
    await _pingPongPlayer.dispose();
    isInit = false;
  }
}
