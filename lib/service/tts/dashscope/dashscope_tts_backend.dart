import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class DashscopeTtsProvider extends TtsServiceProvider {
  static final DashscopeTtsProvider _instance =
      DashscopeTtsProvider._internal();

  factory DashscopeTtsProvider({http.Client? client}) {
    if (client != null) {
      _instance._client = client;
    }
    return _instance;
  }

  DashscopeTtsProvider._internal();

  http.Client _client = http.Client();

  @visibleForTesting
  set client(http.Client value) {
    _client = value;
  }

  static const String _defaultUrl =
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation';
  static const String _defaultModel = 'qwen3-tts-flash';
  static const String _defaultVoice = 'Cherry';
  static const String _defaultLanguageType = 'Auto';

  @override
  TtsService get service => TtsService.dashscope;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateDashScopeTts;

  @override
  Duration get requestTimeout => const Duration(seconds: 25);

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue: L10n.of(context).settingsNarrateDashScopeHelpText,
        link: 'https://bailian.console.aliyun.com/?tab=model#/api-key',
      ),
      ConfigItem(
        key: 'url',
        label: 'URL',
        description: L10n.of(context).settingsNarrateDashScopeUrlDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultUrl,
      ),
      ConfigItem(
        key: 'key',
        label: 'API Key',
        description: L10n.of(context).settingsNarrateDashScopeKeyDescription,
        type: ConfigItemType.password,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'model',
        label: 'Model',
        description: L10n.of(context).settingsNarrateDashScopeModelDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultModel,
      ),
      ConfigItem(
        key: 'voice',
        label: 'Voice',
        description: L10n.of(context).settingsNarrateDashScopeVoiceDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultVoice,
      ),
      ConfigItem(
        key: 'language_type',
        label: 'Language Type',
        description:
            L10n.of(context).settingsNarrateDashScopeLanguageTypeDescription,
        type: ConfigItemType.text,
        defaultValue: _defaultLanguageType,
      ),
      ConfigItem(
        key: 'instructions',
        label: 'Instructions',
        description:
            L10n.of(context).settingsNarrateDashScopeInstructionsDescription,
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
        'language_type': _defaultLanguageType,
        'instructions': '',
      };
    }
    return {
      'url': config['url'] ?? _defaultUrl,
      'key': config['key'] ?? '',
      'model': config['model'] ?? _defaultModel,
      'voice': config['voice'] ?? _defaultVoice,
      'language_type': config['language_type'] ?? _defaultLanguageType,
      'instructions': config['instructions'] ?? '',
    };
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, config);
  }

  @override
  String? validateConfig() {
    final key = getConfig()['key']?.toString().trim();
    if (key == null || key.isEmpty) {
      return 'DashScope TTS config missing (API key)';
    }
    return null;
  }

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final validationError = validateConfig();
    if (validationError != null) {
      throw Exception(validationError);
    }

    final config = getConfig();
    final String url = config['url']?.toString().trim() ?? _defaultUrl;
    final String key = config['key']!.toString().trim();
    final String model = config['model']?.toString().trim() ?? _defaultModel;
    final String languageType =
        config['language_type']?.toString().trim() ?? _defaultLanguageType;
    final String resolvedVoice = resolveVoice(voice);

    final instructions = _buildInstructions(
      config['instructions']?.toString(),
      rate,
    );

    final input = <String, dynamic>{
      'text': text,
      'voice': resolvedVoice,
      if (languageType.isNotEmpty) 'language_type': languageType,
      if (instructions.isNotEmpty) 'instructions': instructions,
    };

    final requestBody = jsonEncode({
      'model': model,
      'input': input,
      'parameters': {
        'response_format': 'mp3',
      },
    });

    final response = await _client
        .post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: requestBody,
        )
        .timeout(requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
          'DashScope TTS failed: ${response.statusCode} ${response.body}');
    }

    final Map<String, dynamic> responseJson;
    try {
      responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception(
          'DashScope TTS failed to parse response: ${response.body}');
    }

    final output = responseJson['output'] as Map<String, dynamic>?;
    final audio = output?['audio'] as Map<String, dynamic>?;
    final audioUrl = audio?['url']?.toString();

    if (audioUrl == null || audioUrl.isEmpty) {
      final code = responseJson['code'];
      final message = responseJson['message'];
      if (code != null || message != null) {
        throw Exception('DashScope TTS error ($code): $message');
      }
      throw Exception(
          'DashScope TTS returned no audio url: ${response.body}');
    }

    final audioResponse =
        await _client.get(Uri.parse(audioUrl)).timeout(requestTimeout);
    if (audioResponse.statusCode == 200) {
      return audioResponse.bodyBytes;
    }

    throw Exception(
        'Failed to download DashScope audio: ${audioResponse.statusCode} ${audioResponse.body}');
  }

  String _buildInstructions(String? base, double rate) {
    final buffer = StringBuffer();
    if (base != null && base.trim().isNotEmpty) {
      buffer.writeln(base.trim());
    }
    if ((rate - 1.0).abs() > 0.05) {
      buffer.writeln('请以${rate.toStringAsFixed(2)}倍速朗读。');
    }
    return buffer.toString().trim();
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    return _curatedVoices;
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) {
      return TtsVoice.fromMap(voiceData);
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  @override
  String getSelectedVoice() {
    final config = getConfig();
    final voice = config['voice']?.toString() ?? '';
    if (voice.isNotEmpty) return voice;
    return _defaultVoice;
  }

  @override
  void setSelectedVoice(String voice) {
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }

  static const List<TtsVoice> _curatedVoices = [
    TtsVoice(
      shortName: 'Cherry',
      name: '芊悦 (Cherry)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '阳光亲切小姐姐，音色自然灵动',
    ),
    TtsVoice(
      shortName: 'Serena',
      name: '苏瑶 (Serena)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '温柔知性小姐姐，温婉从容',
    ),
    TtsVoice(
      shortName: 'Ethan',
      name: '晨煦 (Ethan)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '阳光温暖朝气青年，声线明朗',
    ),
    TtsVoice(
      shortName: 'Chelsie',
      name: '千雪 (Chelsie)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '二次元虚拟女友，活泼甜美',
    ),
    TtsVoice(
      shortName: 'Momo',
      name: '茉兔 (Momo)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '撒娇搞怪，元气满满',
    ),
    TtsVoice(
      shortName: 'Moon',
      name: '月白 (Moon)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '率性帅气小哥哥，质感清亮',
    ),
    TtsVoice(
      shortName: 'Maia',
      name: '四月 (Maia)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '知性温和，娓娓道来',
    ),
    TtsVoice(
      shortName: 'Kai',
      name: '凯 (Kai)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '舒缓沉稳青年，适合朗读伴读',
    ),
    TtsVoice(
      shortName: 'Vincent',
      name: '田叔 (Vincent)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '独特沙哑烟嗓，厚重故事感',
    ),
    TtsVoice(
      shortName: 'Bella',
      name: '萌宝 (Bella)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '天真可爱小萝莉，童真灵动',
    ),
    TtsVoice(
      shortName: 'Arthur',
      name: '徐大爷 (Arthur)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '质朴评书嗓音，沧桑沉稳',
    ),
    TtsVoice(
      shortName: 'Seren',
      name: '小婉 (Seren)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '温和舒眠，睡前夜读陪伴',
    ),
    TtsVoice(
      shortName: 'Eldric Sage',
      name: '沧明子 (Eldric Sage)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '沉稳睿智老者，仙风道骨',
    ),
    TtsVoice(
      shortName: 'Bellona',
      name: '燕铮莺 (Bellona)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '声音洪亮字正腔圆，端庄大气',
    ),
    TtsVoice(
      shortName: 'Vivian',
      name: '十三妹 (Vivian)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '霸气御姐，沉着从容',
    ),
    TtsVoice(
      shortName: 'Neil',
      name: '阿闻 (Neil)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '专业新闻播报男声，字正腔圆',
    ),
    TtsVoice(
      shortName: 'Jada',
      name: '阿珍 (Jada)',
      locale: 'zh-CN',
      gender: 'Female',
      description: '上海方言特色，沪语腔调',
    ),
    TtsVoice(
      shortName: 'Dylan',
      name: '晓东 (Dylan)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '北京方言特色，地道京腔',
    ),
    TtsVoice(
      shortName: 'Marcus',
      name: '秦川 (Marcus)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '陕西方言特色，质朴豪爽',
    ),
    TtsVoice(
      shortName: 'Roy',
      name: '阿杰 (Roy)',
      locale: 'zh-CN',
      gender: 'Male',
      description: '闽南台湾腔调，亲和生活化',
    ),
  ];
}
