import 'dart:convert';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class AliyunApiTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.aliyunApi;

  @override
  String getLabel(BuildContext context) => L10n.of(context).translateAliyun;

  @override
  String mapLanguageCode(LangListEnum lang) {
    const Map<String, String> codeMap = {
      'zh-CN': 'zh',
      'zh-TW': 'zh-tw',
    };
    return codeMap[lang.code] ?? lang.code;
  }

  @override
  Widget translate(String text, LangListEnum from, LangListEnum to,
      {String? contextText, bool isFullText = false}) {
    return convertStreamToWidget(
        translateStream(text, from, to, contextText: contextText));
  }

  @override
  Stream<String> translateStream(String text, LangListEnum from, LangListEnum to,
      {String? contextText, bool isFullText = false}) async* {
    try {
      final config = getConfig();
      final akId = config['access_key_id']?.toString() ?? '';
      final akSecret = config['access_key_secret']?.toString() ?? '';

      if (akId.isEmpty || akSecret.isEmpty) {
        yield* Stream.error(
            Exception('Please set Aliyun AccessKeyId and Secret'));
        return;
      }

      yield "...";

      final params = {
        'Action': 'TranslateGeneral',
        'Version': '2018-10-12',
        'Format': 'JSON',
        'AccessKeyId': akId,
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureNonce': const Uuid().v4(),
        'SignatureVersion': '1.0',
        'Timestamp':
            DateTime.now().toUtc().toIso8601String().split('.')[0] + 'Z',
        'SourceLanguage':
            from == LangListEnum.auto ? 'auto' : mapLanguageCode(from),
        'TargetLanguage': mapLanguageCode(to),
        'SourceText': text,
        'Scene': 'general',
      };

      String percentEncode(String s) => Uri.encodeQueryComponent(s)
          .replaceAll('+', '%20')
          .replaceAll('*', '%2A')
          .replaceAll('%7E', '~');

      final sortedKeys = params.keys.toList()..sort();
      final canonicalQueryString = sortedKeys
          .map((k) => '${percentEncode(k)}=${percentEncode(params[k]!)}')
          .join('&');
      final stringToSign =
          'POST&${percentEncode('/')}&${percentEncode(canonicalQueryString)}';

      final signature = base64Encode(Hmac(sha1, utf8.encode('$akSecret&'))
          .convert(utf8.encode(stringToSign))
          .bytes);
      params['Signature'] = signature;

      final response = await Dio().post(
        'https://mt.aliyuncs.com',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['Code'] != '200') {
          yield* Stream.error(Exception('Aliyun API Error: ${data['Message']}'));
        } else {
          yield data['Data']['Translated'];
        }
      }
    } catch (e) {
      AnxLog.severe("Translate Aliyun Error: $e");
      yield* Stream.error(Exception(e));
    }
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
          key: 'access_key_id',
          label: 'Access Key ID',
          type: ConfigItemType.text,
          defaultValue: ''),
      ConfigItem(
          key: 'access_key_secret',
          label: 'Access Key Secret',
          type: ConfigItemType.password,
          defaultValue: ''),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    return Prefs().getTranslateServiceConfig(service) ??
        {'access_key_id': '', 'access_key_secret': ''};
  }

  @override
  void saveConfig(Map<String, dynamic> config) =>
      Prefs().saveTranslateServiceConfig(service, config);
}
