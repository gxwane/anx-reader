import 'dart:convert';
import 'dart:math';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

const _urlBaiduApi = 'https://fanyi-api.baidu.com/api/trans/vip/translate';

class BaiduApiTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.baiduApi;

  @override
  String getLabel(BuildContext context) => L10n.of(context).translateBaidu;

  @override
  String mapLanguageCode(LangListEnum lang) {
    const Map<String, String> codeMap = {
      'zh-CN': 'zh',
      'zh-TW': 'cht',
      'ja': 'jp',
      'ko': 'kor',
      'fr': 'fra',
      'es': 'spa',
      'ar': 'ara',
    };
    return codeMap[lang.code] ?? lang.code;
  }

  @override
  Widget translate(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) {
    return convertStreamToWidget(
      translateStream(text, from, to, contextText: contextText),
    );
  }

  @override
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) async* {
    try {
      final config = getConfig();
      final appId = config['app_id']?.toString() ?? '';
      final secretKey = config['secret_key']?.toString() ?? '';

      if (appId.isEmpty || secretKey.isEmpty) {
        yield* Stream.error(Exception('Please set Baidu AppID and Secret Key in settings'));
        return;
      }

      yield "...";

      final salt = Random().nextInt(100000).toString();
      final sign = md5.convert(utf8.encode(appId + text + salt + secretKey)).toString();

      final response = await Dio().post(
        _urlBaiduApi,
        data: {
          'q': text,
          'from': from == LangListEnum.auto ? 'auto' : mapLanguageCode(from),
          'to': mapLanguageCode(to),
          'appid': appId,
          'salt': salt,
          'sign': sign,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['error_code'] != null) {
          yield* Stream.error(Exception('Baidu API Error (${data['error_code']}): ${data['error_msg']}'));
        } else {
          final results = data['trans_result'] as List;
          yield results.map((item) => item['dst']).join('\n');
        }
      } else {
        yield* Stream.error(Exception('Baidu API HTTP Error: ${response.statusCode}'));
      }
    } catch (e) {
      AnxLog.severe("Translate Baidu API Error: error=$e");
      yield* Stream.error(Exception(e));
    }
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'app_id',
        label: 'App ID',
        type: ConfigItemType.text,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'secret_key',
        label: 'Secret Key',
        type: ConfigItemType.password,
        defaultValue: '',
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getTranslateServiceConfig(service);
    return config ?? {'app_id': '', 'secret_key': ''};
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveTranslateServiceConfig(service, config);
  }
}
