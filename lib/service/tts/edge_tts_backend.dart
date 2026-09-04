import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

/// Microsoft Edge Read Aloud TTS Provider (Zero-config, high quality neural voices).
class EdgeTtsProvider extends TtsServiceProvider {
  static final EdgeTtsProvider _instance = EdgeTtsProvider._internal();

  factory EdgeTtsProvider() {
    return _instance;
  }

  EdgeTtsProvider._internal();

  static const String _defaultVoice = 'zh-CN-XiaoxiaoNeural';
  static const String _trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _chromiumFullVersion = '143.0.3650.75';
  static const String _secMsGecVersion = '1-$_chromiumFullVersion';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0';
  static final Random _random = Random();
  static const String _wssHost = 'speech.platform.bing.com';
  static const String _wssPath =
      '/consumer/speech/synthesize/readaloud/edge/v1';

  @override
  TtsService get service => TtsService.edge;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateEdgeTts;

  @override
  Duration get requestTimeout => const Duration(seconds: 20);

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue: L10n.of(context).settingsNarrateEdgeHelpText,
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    return {
      'voice': config['voice'] ?? _defaultVoice,
    };
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, config);
  }

  @override
  String getSelectedVoice() {
    final config = getConfig();
    final voice = config['voice']?.toString().trim() ?? '';
    if (voice.isNotEmpty) return voice;
    return _defaultVoice;
  }

  @override
  void setSelectedVoice(String voice) {
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }

  static String _generateMuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('')
        .toUpperCase();
  }

  /// Calculates Sec-MS-GEC security signature based on Windows File Time (ticks).
  static String generateSecMsGec() {
    // Offset in seconds between Windows File Time epoch (1601-01-01) and Unix epoch (1970-01-01)
    const int unixEpochOffset = 11644473600;
    final double unixSeconds =
        DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;
    double ticks = unixSeconds + unixEpochOffset;
    // Align down to 300-second (5-minute) boundary
    ticks -= (ticks % 300);
    // Convert to 100-nanosecond ticks
    ticks *= 10000000;

    final String dataToHash = '${ticks.toStringAsFixed(0)}$_trustedClientToken';
    final Digest digest = sha256.convert(ascii.encode(dataToHash));
    return digest.toString().toUpperCase();
  }

  static String escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _formatRate(double rate) {
    final percent = ((rate - 1.0) * 100).round();
    if (percent >= 0) {
      return '+$percent%';
    }
    return '$percent%';
  }

  static String _formatPitch(double pitch) {
    final hz = ((pitch - 1.0) * 50).round();
    if (hz >= 0) {
      return '+${hz}Hz';
    }
    return '${hz}Hz';
  }

  static String _extractLangCode(String voiceName) {
    final parts = voiceName.split('-');
    if (parts.length >= 2) {
      return '${parts[0]}-${parts[1]}';
    }
    return 'zh-CN';
  }

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final resolvedVoice = resolveVoice(voice);
    final secMsGec = generateSecMsGec();
    final requestId = const Uuid().v4().replaceAll('-', '');

    final uri = Uri.parse(
        'wss://$_wssHost$_wssPath?TrustedClientToken=$_trustedClientToken&ConnectionId=$requestId&Sec-MS-GEC=$secMsGec&Sec-MS-GEC-Version=$_secMsGecVersion');

    final headers = <String, dynamic>{
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'Accept-Encoding': 'gzip, deflate, br',
      'Accept-Language': 'en-US,en;q=0.9',
      'User-Agent': _userAgent,
      'Cookie': 'muid=${_generateMuid()};',
    };

    final completer = Completer<Uint8List>();
    final audioBuilder = BytesBuilder(copy: false);
    WebSocket? webSocket;
    HttpClient? httpClient;

    try {
      httpClient = HttpClient();
      final httpsUri = uri.replace(scheme: 'https');
      final request =
          await httpClient.getUrl(httpsUri).timeout(const Duration(seconds: 8));

      headers.forEach((k, v) {
        request.headers.set(k, v);
      });
      request.headers.set('Upgrade', 'websocket');
      request.headers.set('Connection', 'Upgrade');
      final secWebSocketKey = base64.encode(
          List<int>.generate(16, (_) => _random.nextInt(256)));
      request.headers.set('Sec-WebSocket-Key', secWebSocketKey);
      request.headers.set('Sec-WebSocket-Version', '13');

      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 101) {
        throw WebSocketException(
            'Edge TTS handshake rejected: ${response.statusCode} ${response.reasonPhrase}');
      }

      final socket = await response.detachSocket();
      webSocket = WebSocket.fromUpgradedSocket(socket, serverSide: false);

      // 1. Send speech.config message
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      final configMsg =
          'X-Timestamp:$nowUtc\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n';
      webSocket.add(configMsg);

      // 2. Send SSML message
      final lang = _extractLangCode(resolvedVoice);
      final escapedText = escapeXml(text);
      final rateStr = _formatRate(rate);
      final pitchStr = _formatPitch(pitch);

      final ssml =
          "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$lang'>"
          "<voice name='$resolvedVoice'>"
          "<prosody pitch='$pitchStr' rate='$rateStr' volume='+0%'>"
          "$escapedText"
          '</prosody>'
          '</voice>'
          '</speak>';

      final ssmlMsg =
          'X-RequestId:$requestId\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:$nowUtc\r\nPath:ssml\r\n\r\n$ssml';
      webSocket.add(ssmlMsg);

      webSocket.listen(
        (data) {
          if (data is List<int>) {
            // Binary audio frame
            if (data.length > 2) {
              // 16-bit big-endian header length
              final int headerLength = (data[0] << 8) | data[1];
              final int audioOffset = 2 + headerLength;
              if (data.length > audioOffset) {
                audioBuilder.add(data.sublist(audioOffset));
              }
            }
          } else if (data is String) {
            // Text control message
            if (data.contains('Path:turn.end')) {
              if (!completer.isCompleted) {
                completer.complete(audioBuilder.takeBytes());
              }
            }
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(
                Exception('Edge-TTS WebSocket stream error: $error'));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            final bytes = audioBuilder.takeBytes();
            if (bytes.isNotEmpty) {
              completer.complete(bytes);
            } else {
              completer.completeError(
                  Exception('Edge-TTS connection closed before audio received'));
            }
          }
        },
        cancelOnError: true,
      );

      final resultBytes = await completer.future.timeout(requestTimeout);
      return resultBytes;
    } catch (e) {
      AnxLog.warning('EdgeTts speak failed: $e');
      rethrow;
    } finally {
      try {
        await webSocket?.close(WebSocketStatus.normalClosure);
      } catch (_) {}
      httpClient?.close(force: true);
    }
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    return _edgeVoices;
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) {
      return TtsVoice.fromMap(voiceData);
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  /// Rich curated list of Microsoft Edge Neural Voices (Chinese & international).
  static const List<TtsVoice> _edgeVoices = [
    // Chinese Mainland (Mandarin)
    TtsVoice(
      shortName: 'zh-CN-XiaoxiaoNeural',
      name: '晓晓 (温暖自然)',
      locale: 'zh-CN',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'zh-CN-YunxiNeural',
      name: '云希 (沉稳阳光)',
      locale: 'zh-CN',
      gender: 'Male',
    ),
    TtsVoice(
      shortName: 'zh-CN-YunjianNeural',
      name: '云健 (评书纪实)',
      locale: 'zh-CN',
      gender: 'Male',
    ),
    TtsVoice(
      shortName: 'zh-CN-XiaoyiNeural',
      name: '小艺 (清爽随和)',
      locale: 'zh-CN',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'zh-CN-YunyangNeural',
      name: '云扬 (新闻播报)',
      locale: 'zh-CN',
      gender: 'Male',
    ),
    TtsVoice(
      shortName: 'zh-CN-YunxiaNeural',
      name: '云夏 (活泼少年)',
      locale: 'zh-CN',
      gender: 'Male',
    ),
    // Chinese Dialects & Regional
    TtsVoice(
      shortName: 'zh-CN-liaoning-XiaobeiNeural',
      name: '晓北 (东北方言·女)',
      locale: 'zh-CN',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'zh-CN-shaanxi-XiaoniNeural',
      name: '晓妮 (陕西方言·女)',
      locale: 'zh-CN',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'zh-HK-HiuMaanNeural',
      name: '晓曼 (粤语·女)',
      locale: 'zh-HK',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'zh-HK-WanLungNeural',
      name: '云龙 (粤语·男)',
      locale: 'zh-HK',
      gender: 'Male',
    ),
    TtsVoice(
      shortName: 'zh-TW-HsiaoChenNeural',
      name: '晓臻 (台湾国语·女)',
      locale: 'zh-TW',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'zh-TW-YunJheNeural',
      name: '云哲 (台湾国语·男)',
      locale: 'zh-TW',
      gender: 'Male',
    ),
    // English (US & UK)
    TtsVoice(
      shortName: 'en-US-JennyNeural',
      name: 'Jenny (US Female)',
      locale: 'en-US',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'en-US-GuyNeural',
      name: 'Guy (US Male)',
      locale: 'en-US',
      gender: 'Male',
    ),
    TtsVoice(
      shortName: 'en-US-AriaNeural',
      name: 'Aria (US Female)',
      locale: 'en-US',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'en-GB-SoniaNeural',
      name: 'Sonia (UK Female)',
      locale: 'en-GB',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'en-GB-RyanNeural',
      name: 'Ryan (UK Male)',
      locale: 'en-GB',
      gender: 'Male',
    ),
    // Japanese
    TtsVoice(
      shortName: 'ja-JP-NanamiNeural',
      name: '七海 (Japanese Female)',
      locale: 'ja-JP',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'ja-JP-KeitaNeural',
      name: '圭太 (Japanese Male)',
      locale: 'ja-JP',
      gender: 'Male',
    ),
    // French & German
    TtsVoice(
      shortName: 'fr-FR-DeniseNeural',
      name: 'Denise (French Female)',
      locale: 'fr-FR',
      gender: 'Female',
    ),
    TtsVoice(
      shortName: 'de-DE-KatjaNeural',
      name: 'Katja (German Female)',
      locale: 'de-DE',
      gender: 'Female',
    ),
  ];
}
