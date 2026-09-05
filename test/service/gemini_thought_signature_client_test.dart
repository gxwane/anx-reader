import 'dart:convert';
import 'package:anx_reader/service/ai/gemini_thought_signature_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GeminiThoughtSignatureClient Pure Functions (#977)', () {
    test(
      'GIVEN model turn with functionCall and cached signature, WHEN injecting signatures, THEN injects cached signature',
      () {
        final requestJson = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': 'How many pages in this book?'}
              ],
            },
            {
              'role': 'model',
              'parts': [
                {
                  'functionCall': {
                    'name': 'current_reading_metadata',
                    'args': {},
                  }
                }
              ],
            },
            {
              'role': 'user',
              'parts': [
                {
                  'functionResponse': {
                    'name': 'current_reading_metadata',
                    'response': {'pages': 350},
                  }
                }
              ],
            }
          ]
        };

        final cache = {'current_reading_metadata': 'test_real_signature_abc123'};
        final modified = GeminiThoughtSignatureClient.injectThoughtSignatures(
          requestJson,
          cache,
        );

        final modelPart = (modified['contents'] as List)[1]['parts'][0];
        expect(modelPart['thoughtSignature'], equals('test_real_signature_abc123'));
        expect(modelPart['thought_signature'], equals('test_real_signature_abc123'));
      },
    );

    test(
      'GIVEN model turn with functionCall and NO cached signature, WHEN injecting signatures, THEN injects skip_thought_signature_validator fallback',
      () {
        final requestJson = {
          'contents': [
            {
              'role': 'model',
              'parts': [
                {
                  'functionCall': {
                    'name': 'current_reading_metadata',
                    'args': {},
                  }
                }
              ],
            }
          ]
        };

        final modified = GeminiThoughtSignatureClient.injectThoughtSignatures(
          requestJson,
          {}, // empty cache
        );

        final modelPart = (modified['contents'] as List)[0]['parts'][0];
        expect(
          modelPart['thoughtSignature'],
          equals('skip_thought_signature_validator'),
        );
        expect(
          modelPart['thought_signature'],
          equals('skip_thought_signature_validator'),
        );
      },
    );

    test(
      'GIVEN model turn that already has thoughtSignature, WHEN injecting signatures, THEN preserves existing signature',
      () {
        final requestJson = {
          'contents': [
            {
              'role': 'model',
              'parts': [
                {
                  'functionCall': {
                    'name': 'current_reading_metadata',
                    'args': {},
                  },
                  'thoughtSignature': 'existing_sig_xyz',
                }
              ],
            }
          ]
        };

        final modified = GeminiThoughtSignatureClient.injectThoughtSignatures(
          requestJson,
          {'current_reading_metadata': 'different_cache_sig'},
        );

        final modelPart = (modified['contents'] as List)[0]['parts'][0];
        expect(modelPart['thoughtSignature'], equals('existing_sig_xyz'));
      },
    );

    test(
      'GIVEN JSON response with thoughtSignature, WHEN extracting signatures, THEN populates cache correctly',
      () {
        final responseJson = {
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {
                    'functionCall': {
                      'name': 'current_reading_metadata',
                      'args': {},
                    },
                    'thoughtSignature': 'sig_from_gemini_server_789',
                  }
                ]
              }
            }
          ]
        };

        final cache = <String, String>{};
        GeminiThoughtSignatureClient.extractSignaturesFromJson(responseJson, cache);

        expect(cache['current_reading_metadata'], equals('sig_from_gemini_server_789'));
      },
    );

    test(
      'GIVEN SSE chunk text, WHEN extracting signatures, THEN extracts from data: payload',
      () {
        const sseText = '''
data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"current_book_toc","args":{}},"thought_signature":"sig_from_sse_stream_456"}]}}]}

''';

        final cache = <String, String>{};
        GeminiThoughtSignatureClient.extractSignaturesFromSseText(sseText, cache);

        expect(cache['current_book_toc'], equals('sig_from_sse_stream_456'));
      },
    );
  });

  group('GeminiThoughtSignatureClient HTTP Interception (#977)', () {
    test(
      'GIVEN outbound request without signature, WHEN sent via GeminiThoughtSignatureClient, THEN injects signature into payload before dispatching',
      () async {
        http.Request? capturedOutboundRequest;

        final mockHandler = MockClient((request) async {
          capturedOutboundRequest = request;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'role': 'model',
                    'parts': [
                      {'text': 'Here are the details about the book.'}
                    ]
                  }
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = GeminiThoughtSignatureClient(inner: mockHandler);

        final originalRequest = http.Request(
          'POST',
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
        )
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({
            'contents': [
              {
                'role': 'model',
                'parts': [
                  {
                    'functionCall': {
                      'name': 'current_reading_metadata',
                      'args': {},
                    }
                  }
                ]
              }
            ]
          });

        await client.send(originalRequest);

        expect(capturedOutboundRequest, isNotNull);
        final parsedOutboundBody = jsonDecode(capturedOutboundRequest!.body) as Map<String, dynamic>;
        final modelPart = (parsedOutboundBody['contents'] as List)[0]['parts'][0];

        expect(modelPart['thoughtSignature'], equals('skip_thought_signature_validator'));
        expect(modelPart['thought_signature'], equals('skip_thought_signature_validator'));
      },
    );

    test(
      'GIVEN non-Google URL or non-JSON body, WHEN sent via client, THEN passes through untouched',
      () async {
        http.Request? capturedOutboundRequest;

        final mockHandler = MockClient((request) async {
          capturedOutboundRequest = request;
          return http.Response('OK', 200);
        });

        final client = GeminiThoughtSignatureClient(inner: mockHandler);

        final originalRequest = http.Request(
          'POST',
          Uri.parse('https://api.openai.com/v1/chat/completions'),
        )
          ..body = 'plain_raw_text';

        await client.send(originalRequest);

        expect(capturedOutboundRequest, isNotNull);
        expect(capturedOutboundRequest!.body, equals('plain_raw_text'));
      },
    );
  });
}
