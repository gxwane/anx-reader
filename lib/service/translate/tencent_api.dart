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

class TencentApiTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.tencentApi;

  @override
  String getLabel(BuildContext context) => L10n.of(context).translateTencent;

  @override
  String mapLanguageCode(LangListEnum lang) {
    const Map<String, String> codeMap = {
      'zh-CN': 'zh',
      'zh-TW': 'zh-TW',
      'ja': 'ja',
      'ko': 'ko',
      'fr': 'fr',
      'es': 'es',
      'ar': 'ar',
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
      final secretId = config['secret_id']?.toString() ?? '';
      final secretKey = config['secret_key']?.toString() ?? '';
      final region = config['region']?.toString() ?? '';

      if (secretId.isEmpty || secretKey.isEmpty) {
        yield* Stream.error(Exception('Please set Tencent SecretID and Secret Key in settings'));
        return;
      }

      yield "...";

      const host = 'tmt.tencentcloudapi.com';
      const service = 'tmt';
      const version = '2018-03-21';
      const action = 'TextTranslate';
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true)
          .toString()
          .substring(0, 10);

      final payload = jsonEncode({
        'SourceText': text,
        'Source': from == LangListEnum.auto ? 'auto' : mapLanguageCode(from),
        'Target': mapLanguageCode(to),
        'ProjectId': 0,
      });

      // TC3 Signature process
      final hashedRequestPayload = sha256.convert(utf8.encode(payload)).toString();
      const canonicalUri = '/';
      const canonicalQueryString = '';
      final canonicalHeaders = 'content-type:application/json\nhost:$host\nx-tc-action:${action.toLowerCase()}\n';
      const signedHeaders = 'content-type;host;x-tc-action';
      
      final canonicalRequest = 'POST\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$hashedRequestPayload';
      
      const algorithm = 'TC3-HMAC-SHA256';
      final credentialScope = '$date/$service/tc3_request';
      final hashedCanonicalRequest = sha256.convert(utf8.encode(canonicalRequest)).toString();
      final stringToSign = '$algorithm\n$timestamp\n$credentialScope\n$hashedCanonicalRequest';

      final kDate = Hmac(sha256, utf8.encode('TC3' + secretKey)).convert(utf8.encode(date)).bytes;
      final kService = Hmac(sha256, kDate).convert(utf8.encode(service)).bytes;
      final kSigning = Hmac(sha256, kService).convert(utf8.encode('tc3_request')).bytes;
      final signature = Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();

      final authorization = '$algorithm Credential=$secretId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

      final response = await Dio().post(
        'https://$host',
        data: payload,
        options: Options(
          headers: {
            'Authorization': authorization,
            'Content-Type': 'application/json',
            'Host': host,
            'X-TC-Action': action,
            'X-TC-Timestamp': timestamp.toString(),
            'X-TC-Version': version,
            'X-TC-Region': region,
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['Response']['Error'] != null) {
          yield* Stream.error(Exception('Tencent API Error: ${data['Response']['Error']['Message']}'));
        } else {
          yield data['Response']['TargetText'];
        }
      } else {
        yield* Stream.error(Exception('Tencent API HTTP Error: ${response.statusCode}'));
      }
    } catch (e) {
      AnxLog.severe("Translate Tencent API Error: error=$e");
      yield* Stream.error(Exception(e));
    }
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'secret_id',
        label: 'Secret ID',
        type: ConfigItemType.text,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'secret_key',
        label: 'Secret Key',
        type: ConfigItemType.password,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'region',
        label: 'Region',
        type: ConfigItemType.text,
        defaultValue: 'ap-guangzhou',
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getTranslateServiceConfig(service);
    return config ?? {'secret_id': '', 'secret_key': '', 'region': 'ap-guangzhou'};
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveTranslateServiceConfig(service, config);
  }
}
