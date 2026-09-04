import 'dart:async';
import 'dart:typed_data';
import 'package:anx_reader/utils/log/common.dart';
import 'package:audioplayers/audioplayers.dart';

/// Detects standard audio format mime-type by inspecting magic bytes in the header.
String detectAudioMimeType(Uint8List bytes) {
  if (bytes.length >= 12) {
    // RIFF....WAVE (WAV)
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45) {
      return 'audio/wav';
    }
    // OggS (OGG / Opus / Vorbis)
    if (bytes[0] == 0x4F &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53) {
      return 'audio/ogg';
    }
    // ID3 (MP3 with ID3v2 container)
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      return 'audio/mp3';
    }
  }
  if (bytes.length >= 2) {
    // MP3 raw frame sync (11 bits set: 0xFF followed by 0xEx or 0xFx)
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return 'audio/mp3';
    }
  }
  return 'audio/mp3';
}

/// Dual-buffered ping-pong audio player engine.
///
/// Maintains two persistent [AudioPlayer] instances ([_playerA] and [_playerB])
/// to enable gapless pre-warming and sub-10ms intra-sentence transitions.
class PingPongAudioPlayer {
  AudioPlayer? _playerA;
  AudioPlayer? _playerB;
  int _activePlayerIndex = 0; // 0 for A, 1 for B
  double _volume = 1.0;

  StreamSubscription<void>? _subA;
  StreamSubscription<void>? _subB;

  StreamController<int> _completeController =
      StreamController<int>.broadcast();
  Completer<void>? _initCompleter;

  /// Stream fired when the currently active player finishes playback.
  /// Emits the player index (0 for A, 1 for B).
  Stream<int> get onActivePlayerComplete => _completeController.stream;

  AudioPlayer get activePlayer =>
      _activePlayerIndex == 0 ? _playerA! : _playerB!;

  AudioPlayer get nextPlayer =>
      _activePlayerIndex == 0 ? _playerB! : _playerA!;

  int get activeIndex => _activePlayerIndex;

  bool get isInitialized => _playerA != null && _playerB != null;

  /// Ensures both persistent player instances are created and configured.
  Future<void> ensureInitialized({double volume = 1.0}) async {
    _volume = volume;
    if (isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      if (_completeController.isClosed) {
        _completeController = StreamController<int>.broadcast();
      }

      _playerA = AudioPlayer();
      _playerB = AudioPlayer();

      await Future.wait([
        _playerA!.setReleaseMode(ReleaseMode.stop),
        _playerB!.setReleaseMode(ReleaseMode.stop),
        _playerA!.setPlayerMode(PlayerMode.mediaPlayer),
        _playerB!.setPlayerMode(PlayerMode.mediaPlayer),
        _playerA!.setVolume(_volume),
        _playerB!.setVolume(_volume),
      ]);

      _subA = _playerA!.onPlayerComplete.listen((_) {
        if (_activePlayerIndex == 0 && !_completeController.isClosed) {
          _completeController.add(0);
        }
      });

      _subB = _playerB!.onPlayerComplete.listen((_) {
        if (_activePlayerIndex == 1 && !_completeController.isClosed) {
          _completeController.add(1);
        }
      });
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  /// Sets volume on both player instances.
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (!isInitialized) return;
    await Future.wait([
      _playerA!.setVolume(volume),
      _playerB!.setVolume(volume),
    ]);
  }

  bool _isNextPrewarmed = false;

  /// Cancels any pre-warmed audio on the next player (e.g. when pitch/rate changes).
  Future<void> cancelPrewarm() async {
    _isNextPrewarmed = false;
    if (isInitialized) {
      try {
        await nextPlayer.stop();
      } catch (_) {}
    }
  }

  /// Pre-warms the idle next player by assigning its audio byte source.
  ///
  /// This decodes and prepares the audio buffer in advance on the idle player
  /// while the active player is still playing.
  Future<void> prewarmNext(Uint8List audioBytes, {String? mimeType}) async {
    if (!isInitialized) await ensureInitialized(volume: _volume);
    final detectedMime = mimeType ?? detectAudioMimeType(audioBytes);
    final source = BytesSource(audioBytes, mimeType: detectedMime);
    try {
      await nextPlayer.setSource(source);
      _isNextPrewarmed = true;
    } catch (e) {
      _isNextPrewarmed = false;
      AnxLog.warning('PingPongPlayer: failed to prewarm next player: $e');
    }
  }

  /// Starts playback directly on the active player (for initial start or seek).
  Future<void> playActive(Uint8List audioBytes, {String? mimeType}) async {
    if (!isInitialized) await ensureInitialized(volume: _volume);
    final detectedMime = mimeType ?? detectAudioMimeType(audioBytes);
    final source = BytesSource(audioBytes, mimeType: detectedMime);
    _isNextPrewarmed = false;
    await activePlayer.play(source, volume: _volume);
  }

  /// Switches active player to the pre-warmed player and starts playback immediately.
  ///
  /// Returns the newly active player index.
  Future<int> advanceToNext({Uint8List? fallbackBytes}) async {
    if (!isInitialized) await ensureInitialized(volume: _volume);

    // Stop previous player
    final oldPlayer = activePlayer;
    unawaited(oldPlayer.stop());

    // Toggle index
    _activePlayerIndex = _activePlayerIndex == 0 ? 1 : 0;
    final newActivePlayer = activePlayer;
    final wasPrewarmed = _isNextPrewarmed;
    _isNextPrewarmed = false;

    if (wasPrewarmed) {
      try {
        await newActivePlayer.resume();
        return _activePlayerIndex;
      } catch (e) {
        AnxLog.warning(
            'PingPongPlayer: prewarmed resume failed, falling back to play: $e');
      }
    }

    if (fallbackBytes != null) {
      final mime = detectAudioMimeType(fallbackBytes);
      await newActivePlayer.play(BytesSource(fallbackBytes, mimeType: mime),
          volume: _volume);
    }

    return _activePlayerIndex;
  }

  /// Pauses the currently active player.
  Future<void> pause() async {
    if (!isInitialized) return;
    await activePlayer.pause();
  }

  /// Resumes playback on the currently active player.
  Future<void> resume() async {
    if (!isInitialized) return;
    await activePlayer.resume();
  }

  /// Stops both players. Does NOT dispose instances, allowing instant reuse.
  Future<void> stop() async {
    _isNextPrewarmed = false;
    if (!isInitialized) return;
    await Future.wait([
      _playerA!.stop(),
      _playerB!.stop(),
    ]);
  }

  /// Fully disposes player instances and streams upon application shutdown.
  Future<void> dispose() async {
    await stop();
    await _subA?.cancel();
    await _subB?.cancel();
    _subA = null;
    _subB = null;
    await Future.wait([
      if (_playerA != null) _playerA!.dispose(),
      if (_playerB != null) _playerB!.dispose(),
    ]);
    _playerA = null;
    _playerB = null;
    if (!_completeController.isClosed) {
      await _completeController.close();
    }
  }
}
