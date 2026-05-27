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

class VolcengineApiTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.volcengineApi;

  @override
  String getLabel(BuildContext context) => L10n.of(context).translateVolcengine;

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
      final ak = config['access_key']?.toString() ?? '';
      final sk = config['secret_key']?.toString() ?? '';
      final region = config['region']?.toString() ?? 'cn-north-1';

      if (ak.isEmpty || sk.isEmpty) {
        yield* Stream.error(
            Exception('Please set Volcengine AccessKey and Secret Key'));
        return;
      }

      yield "...";

      const serviceName = 'translate';
      const host = 'open.volcengineapi.com';
      const action = 'TranslateText';
      const version = '2020-06-01';

      final now = DateTime.now().toUtc();
      final date = now.toString().substring(0, 10).replaceAll('-', '');
      final timestamp = now
              .toIso8601String()
              .split('.')[0]
              .replaceAll('-', '')
              .replaceAll(':', '') +
          'Z';

      final Map<String, dynamic> bodyMap = {
        'TargetLanguage': mapLanguageCode(to),
        'TextList': [text],
      };
      if (from != LangListEnum.auto) {
        bodyMap['SourceLanguage'] = mapLanguageCode(from);
      }
      final body = jsonEncode(bodyMap);

      final payloadHash = sha256.convert(utf8.encode(body)).toString();
      final canonicalHeaders =
          'content-type:application/json\nhost:$host\nx-content-sha256:$payloadHash\nx-date:$timestamp\n';
      const signedHeaders = 'content-type;host;x-content-sha256;x-date';
      final canonicalRequest =
          'POST\n/\nAction=$action&Version=$version\n$canonicalHeaders\n$signedHeaders\n$payloadHash';

      final stringToSign =
          'HMAC-SHA256\n$timestamp\n$date/$region/$serviceName/request\n${sha256.convert(utf8.encode(canonicalRequest))}';

      List<int> sign(List<int> key, String msg) =>
          Hmac(sha256, key).convert(utf8.encode(msg)).bytes;
      final kDate = sign(utf8.encode(sk), date);
      final kRegion = sign(kDate, region);
      final kService = sign(kRegion, serviceName);
      final kSigning = sign(kService, 'request');
      final signature =
          Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();

      final authorization =
          'HMAC-SHA256 Credential=$ak/$date/$region/$serviceName/request, SignedHeaders=$signedHeaders, Signature=$signature';

      final response = await Dio().post(
        'https://$host?Action=$action&Version=$version',
        data: body,
        options: Options(headers: {
          'Authorization': authorization,
          'Content-Type': 'application/json',
          'X-Date': timestamp,
          'X-Content-Sha256': payloadHash,
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['ResponseMetadata']['Error'] != null) {
          yield* Stream.error(Exception(
              'Volcengine API Error: ${data['ResponseMetadata']['Error']['Message']}'));
        } else {
          yield data['TranslationList'][0]['Translation'];
        }
      }
    } catch (e) {
      AnxLog.severe("Translate Volcengine Error: $e");
      yield* Stream.error(Exception(e));
    }
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
          key: 'access_key',
          label: 'Access Key',
          type: ConfigItemType.text,
          defaultValue: ''),
      ConfigItem(
          key: 'secret_key',
          label: 'Secret Key',
          type: ConfigItemType.password,
          defaultValue: ''),
      ConfigItem(
          key: 'region',
          label: 'Region',
          type: ConfigItemType.text,
          defaultValue: 'cn-north-1'),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    return Prefs().getTranslateServiceConfig(service) ??
        {'access_key': '', 'secret_key': '', 'region': 'cn-north-1'};
  }

  @override
  void saveConfig(Map<String, dynamic> config) =>
      Prefs().saveTranslateServiceConfig(service, config);
}
