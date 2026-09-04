import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// Local / Self-Hosted TTS Provider (CosyVoice, GPT-SoVITS, ChatTTS, Piper, Ollama, etc.)
/// Compatible with OpenAI audio speech REST specification.
class SelfHostedTtsProvider extends TtsServiceProvider {
  static final SelfHostedTtsProvider _instance =
      SelfHostedTtsProvider._internal();

  factory SelfHostedTtsProvider() {
    return _instance;
  }

  SelfHostedTtsProvider._internal();

  http.Client? httpClientOverride;

  static const String _defaultUrl = 'http://127.0.0.1:8000/v1/audio/speech';
  static const String _defaultModel = 'tts-1';
  static const String _defaultVoice = 'default';

  @override
  TtsService get service => TtsService.selfHosted;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateSelfHostedTts;

  /// Dynamic request timeout (30 seconds) to accommodate local GPU/CPU model inference.
  @override
  Duration get requestTimeout => const Duration(seconds: 30);

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue: L10n.of(context).settingsNarrateSelfHostedHelpText,
      ),
      ConfigItem(
        key: 'url',
        label: 'URL',
        description: L10n.of(context).settingsNarrateSelfHostedUrlDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultUrl,
      ),
      ConfigItem(
        key: 'key',
        label: 'API Key (Optional)',
        description: L10n.of(context).settingsNarrateSelfHostedKeyDescription,
        type: ConfigItemType.password,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'model',
        label: 'Model',
        description: L10n.of(context).settingsNarrateSelfHostedModelDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultModel,
      ),
      ConfigItem(
        key: 'voice',
        label: 'Voice',
        description: L10n.of(context).settingsNarrateSelfHostedVoiceDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultVoice,
      ),
      ConfigItem(
        key: 'instructions',
        label: 'Instructions',
        description:
            L10n.of(context).settingsNarrateOpenAiInstructionsDescription,
        type: ConfigItemType.text,
        defaultValue: '',
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    if (config.isEmpty) {
      return {
        'url': _defaultUrl,
        'key': '',
        'model': _defaultModel,
        'voice': _defaultVoice,
        'instructions': '',
      };
    }
    return {
      'url': config['url'] ?? _defaultUrl,
      'key': config['key'] ?? '',
      'model': config['model'] ?? _defaultModel,
      'voice': config['voice'] ?? _defaultVoice,
      'instructions': config['instructions'] ?? '',
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

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final config = getConfig();
    final String rawUrl = config['url']?.toString().trim() ?? _defaultUrl;
    final String url = rawUrl.isEmpty ? _defaultUrl : rawUrl;
    final String? key = config['key']?.toString().trim();
    final String model = config['model']?.toString().trim() ?? _defaultModel;
    final String resolvedVoice = resolveVoice(voice);

    final instructions = _buildInstructions(
      config['instructions']?.toString(),
      rate,
      pitch,
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key',
    };

    final body = jsonEncode({
      'model': model.isEmpty ? _defaultModel : model,
      'voice': resolvedVoice.isEmpty ? _defaultVoice : resolvedVoice,
      'input': text,
      'speed': rate,
      if (instructions.isNotEmpty) 'instructions': instructions,
      'response_format': 'mp3',
    });

    final client = httpClientOverride ?? http.Client();
    try {
      final response = await client.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';
        final isJsonOrHtmlHeader = contentType.contains('application/json') ||
            contentType.contains('text/html');

        // Check first non-whitespace byte
        int firstNonWhitespace = 0;
        for (int i = 0; i < bytes.length && i < 16; i++) {
          final b = bytes[i];
          if (b != 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) {
            firstNonWhitespace = b;
            break;
          }
        }

        // Non-audio text/json error guard (L-1)
        if (isJsonOrHtmlHeader ||
            firstNonWhitespace == 0x7B ||
            firstNonWhitespace == 0x3C) {
          String? decoded;
          try {
            decoded = utf8.decode(bytes);
          } catch (_) {
            // If utf8 decode fails, it is binary audio
          }
          if (decoded != null &&
              (decoded.contains('"error"') ||
                  decoded.toLowerCase().contains('<html'))) {
            throw Exception(
                'Self-Hosted TTS returned non-audio body: $decoded');
          }
        }
        return bytes;
      }

      throw Exception(
          'Self-Hosted TTS failed: ${response.statusCode} ${response.body}');
    } finally {
      if (httpClientOverride == null) {
        client.close();
      }
    }
  }

  String _buildInstructions(String? base, double rate, double pitch) {
    final buffer = StringBuffer();
    if (base != null && base.trim().isNotEmpty) {
      buffer.writeln(base.trim());
    }
    if ((rate - 1.0).abs() > 0.01) {
      buffer.writeln('Please speak at a speed of ${rate.toStringAsFixed(2)}x.');
    }
    if ((pitch - 1.0).abs() > 0.01) {
      buffer.writeln('Please use a pitch of ${pitch.toStringAsFixed(2)}x.');
    }
    return buffer.toString().trim();
  }

  /// Normalizes base URL for voice/model discovery (M-1)
  String _getBaseUrl(String rawUrl) {
    var uri = Uri.tryParse(rawUrl);
    if (uri == null) return 'http://127.0.0.1:8000/v1';

    String path = uri.path;
    if (path.endsWith('/audio/speech')) {
      path = path.substring(0, path.length - '/audio/speech'.length);
    } else if (path.endsWith('/audio/speech/')) {
      path = path.substring(0, path.length - '/audio/speech/'.length);
    } else if (path.endsWith('/speech')) {
      path = path.substring(0, path.length - '/speech'.length);
    }

    return uri.replace(path: path).toString().replaceAll(RegExp(r'/+$'), '');
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    final config = getConfig();
    final String rawUrl = config['url']?.toString().trim() ?? _defaultUrl;
    final String? key = config['key']?.toString().trim();
    final String baseUrl = _getBaseUrl(rawUrl);

    final headers = <String, String>{
      'Accept': 'application/json',
      if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key',
    };

    final client = httpClientOverride ?? http.Client();
    try {
      // 1. Try GET /voices or /audio/voices
      for (final endpoint in ['$baseUrl/audio/voices', '$baseUrl/voices', '$baseUrl/models']) {
        try {
          final res = await client
              .get(Uri.parse(endpoint), headers: headers)
              .timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final dynamic json = jsonDecode(utf8.decode(res.bodyBytes));
            final voices = _parseVoicesFromJson(json);
            if (voices.isNotEmpty) return voices;
          }
        } catch (_) {}
      }
    } finally {
      if (httpClientOverride == null) {
        client.close();
      }
    }

    // Graceful fallback to currently selected voice or presets
    final currentVoice = getSelectedVoice();
    final candidates = [
      TtsVoice(shortName: currentVoice, name: currentVoice, locale: 'zh-CN'),
      const TtsVoice(shortName: 'default', name: 'Default', locale: 'zh-CN'),
      const TtsVoice(shortName: 'alloy', name: 'Alloy', locale: 'en-US'),
      const TtsVoice(shortName: 'echo', name: 'Echo', locale: 'en-US'),
    ];
    final seen = <String>{};
    return candidates.where((v) => seen.add(v.shortName)).toList();
  }

  List<TtsVoice> _parseVoicesFromJson(dynamic json) {
    List<dynamic> list = [];
    if (json is List) {
      list = json;
    } else if (json is Map<String, dynamic>) {
      if (json['voices'] is List) {
        list = json['voices'];
      } else if (json['data'] is List) {
        list = json['data'];
      } else if (json['models'] is List) {
        list = json['models'];
      }
    }

    final voices = <TtsVoice>[];
    for (final item in list) {
      if (item is String && item.trim().isNotEmpty) {
        voices.add(TtsVoice(
          shortName: item.trim(),
          name: item.trim(),
          locale: 'zh-CN',
        ));
      } else if (item is Map<String, dynamic>) {
        final id = item['id']?.toString() ??
            item['voice']?.toString() ??
            item['name']?.toString() ??
            item['shortName']?.toString();
        if (id != null && id.trim().isNotEmpty) {
          voices.add(TtsVoice(
            shortName: id.trim(),
            name: item['name']?.toString() ?? id.trim(),
            locale: item['locale']?.toString() ??
                item['language']?.toString() ??
                'zh-CN',
            gender: item['gender']?.toString() ?? '',
          ));
        }
      }
    }
    return voices;
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) {
      return TtsVoice.fromMap(voiceData);
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }
}
