import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/utils/log/common.dart';
import 'package:http/http.dart' as http;

/// An HTTP client interceptor that preserves and injects Gemini reasoning
/// `thought_signature` / `thoughtSignature` across tool calling turns (#977).
///
/// Gemini 2.0 / 2.5 / 3.0 thinking models strictly validate that previous
/// `functionCall` turns in conversation history retain the encrypted
/// `thought_signature` issued by Google. When third-party libraries (like
/// `langchain_google`) strip or omit this field, Google's API rejects subsequent
/// function responses with a 400 Bad Request error.
///
/// This client transparently captures real signatures from model responses and
/// restores them in outbound request payloads, falling back to Google's official
/// sentinel bypass token `skip_thought_signature_validator` when needed.
class GeminiThoughtSignatureClient extends http.BaseClient {
  GeminiThoughtSignatureClient({
    http.Client? inner,
    this.fallbackSignature = 'skip_thought_signature_validator',
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final String fallbackSignature;

  /// Cache of function names to their most recent thought signatures.
  final Map<String, String> _signatureCache = <String, String>{};
  static const int _maxCacheEntries = 128;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final effectiveRequest = _inspectAndModifyOutboundRequest(request);
    final streamedResponse = await _inner.send(effectiveRequest);

    final contentType = streamedResponse.headers['content-type'] ?? '';
    final isGemini = _isGeminiApiRequest(effectiveRequest);

    if (streamedResponse.statusCode == 200 && isGemini) {
      if (contentType.contains('text/event-stream')) {
        return _interceptSseStream(streamedResponse);
      }
      if (contentType.contains('application/json')) {
        return _interceptJsonResponse(streamedResponse);
      }
    }

    return streamedResponse;
  }

  http.BaseRequest _inspectAndModifyOutboundRequest(http.BaseRequest request) {
    if (request is! http.Request || !_isGeminiApiRequest(request)) {
      return request;
    }
    try {
      final bodyText = request.body;
      if (!bodyText.contains('"functionCall"') || !bodyText.contains('"contents"')) {
        return request;
      }
      final dynamic decoded = jsonDecode(bodyText);
      if (decoded is Map<String, dynamic>) {
        final modified = injectThoughtSignatures(
          decoded,
          _signatureCache,
          fallbackSignature: fallbackSignature,
        );
        return http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..body = jsonEncode(modified);
      }
    } catch (error) {
      AnxLog.warning('GeminiThoughtSignatureClient: failed to inspect outbound request: $error');
    }
    return request;
  }

  bool _isGeminiApiRequest(http.BaseRequest request) {
    final host = request.url.host.toLowerCase();
    final path = request.url.path.toLowerCase();
    return host.contains('googleapis.com') ||
        path.contains('generatecontent') ||
        path.contains('streamgeneratecontent');
  }

  http.StreamedResponse _interceptSseStream(http.StreamedResponse response) {
    final controller = StreamController<List<int>>();

    response.stream.transform(utf8.decoder).listen(
      (chunk) {
        try {
          extractSignaturesFromSseText(chunk, _signatureCache);
        } catch (_) {}
        controller.add(utf8.encode(chunk));
      },
      onError: controller.addError,
      onDone: controller.close,
      cancelOnError: false,
    );

    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  Future<http.StreamedResponse> _interceptJsonResponse(http.StreamedResponse response) async {
    final bytes = await response.stream.toBytes();
    try {
      final text = utf8.decode(bytes);
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        extractSignaturesFromJson(decoded, _signatureCache);
      }
    } catch (_) {}

    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  /// Pure function: injects `thoughtSignature` and `thought_signature` into
  /// model turns containing `functionCall` if missing.
  static Map<String, dynamic> injectThoughtSignatures(
    Map<String, dynamic> requestJson,
    Map<String, String> signatureCache, {
    String fallbackSignature = 'skip_thought_signature_validator',
  }) {
    final contents = requestJson['contents'];
    if (contents is! List) return requestJson;

    for (final content in contents) {
      if (content is Map && content['role'] == 'model') {
        _injectIntoModelContent(content, signatureCache, fallbackSignature);
      }
    }
    return requestJson;
  }

  static void _injectIntoModelContent(
    Map content,
    Map<String, String> signatureCache,
    String fallbackSignature,
  ) {
    final parts = content['parts'];
    if (parts is! List) return;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part is! Map || !part.containsKey('functionCall')) continue;
      if (part.containsKey('thoughtSignature') || part.containsKey('thought_signature')) continue;

      _injectIntoPart(content, parts, i, part, signatureCache, fallbackSignature);
    }
  }

  static void _injectIntoPart(
    Map content,
    List parts,
    int index,
    Map part,
    Map<String, String> signatureCache,
    String fallbackSignature,
  ) {
    final fc = part['functionCall'];
    final fnName = fc is Map ? fc['name']?.toString() : null;
    final signature = (fnName != null ? signatureCache[fnName] : null) ?? fallbackSignature;

    try {
      part['thoughtSignature'] = signature;
      part['thought_signature'] = signature;
    } catch (_) {
      final newPart = Map<String, dynamic>.from(part);
      newPart['thoughtSignature'] = signature;
      newPart['thought_signature'] = signature;
      try {
        parts[index] = newPart;
      } catch (_) {
        final newParts = List<dynamic>.from(parts);
        newParts[index] = newPart;
        content['parts'] = newParts;
      }
    }
  }

  /// Pure function: extracts thought signatures from a Gemini JSON response.
  static void extractSignaturesFromJson(
    Map<String, dynamic> responseJson,
    Map<String, String> targetCache,
  ) {
    final candidates = responseJson['candidates'];
    if (candidates is! List) return;

    for (final candidate in candidates) {
      if (candidate is! Map<String, dynamic>) continue;
      final content = candidate['content'];
      if (content is! Map<String, dynamic>) continue;
      final parts = content['parts'];
      if (parts is! List) continue;

      for (final part in parts) {
        if (part is Map<String, dynamic>) {
          _extractFromPart(part, targetCache);
        }
      }
    }
  }

  static void _extractFromPart(
    Map<String, dynamic> part,
    Map<String, String> targetCache,
  ) {
    final fc = part['functionCall'];
    if (fc is! Map<String, dynamic>) return;

    final fnName = fc['name']?.toString();
    final sig = part['thoughtSignature']?.toString() ??
        part['thought_signature']?.toString();

    if (fnName != null && sig != null && sig.isNotEmpty) {
      if (targetCache.length >= _maxCacheEntries) {
        targetCache.remove(targetCache.keys.first);
      }
      targetCache[fnName] = sig;
    }
  }

  /// Pure function: extracts thought signatures from an SSE text chunk.
  static void extractSignaturesFromSseText(
    String sseChunk,
    Map<String, String> targetCache,
  ) {
    final lines = sseChunk.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;

      final jsonPayload = trimmed.substring(5).trim();
      if (jsonPayload.isEmpty) continue;

      try {
        final dynamic decoded = jsonDecode(jsonPayload);
        if (decoded is Map<String, dynamic>) {
          extractSignaturesFromJson(decoded, targetCache);
        }
      } catch (_) {}
    }
  }
}
