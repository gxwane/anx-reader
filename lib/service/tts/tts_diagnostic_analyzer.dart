enum TtsDiagnosticScenario {
  unreachable, // 502, 503, 504, Connection Refused, 10061, SocketException, ClientException
  authFailed,  // 401, 403
  notFound,    // 404
  timeout,     // TimeoutException
  unknown,     // Generic/Unknown
}

enum TtsDiagnosticSuggestion {
  checkServerRunning,
  checkPort,
  proxyLoopback,
  lanWifiFirewall,
  publicDns,
  checkApiKey,
  checkEndpointPath,
  checkGpuTimeout,
  genericError,
}

class NetworkTargetInfo {
  final String host;
  final String port;
  final bool isLocalhost;
  final bool isPrivateLan;
  final bool isSecure;

  const NetworkTargetInfo({
    required this.host,
    required this.port,
    required this.isLocalhost,
    required this.isPrivateLan,
    required this.isSecure,
  });

  factory NetworkTargetInfo.fromUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return const NetworkTargetInfo(
        host: 'localhost',
        port: '80',
        isLocalhost: true,
        isPrivateLan: false,
        isSecure: false,
      );
    }

    // Pre-normalize scheme-less URLs to prevent Uri.tryParse from losing host and port (C-1)
    var trimmed = rawUrl.trim();
    if (!trimmed.contains('://')) {
      trimmed = 'http://$trimmed';
    }

    final uri = Uri.tryParse(trimmed);
    final scheme = uri?.scheme.toLowerCase() ?? 'http';
    final isSecure = scheme == 'https';
    final host = uri?.host.isNotEmpty == true ? uri!.host : 'localhost';

    final int portNum = (uri?.hasPort == true && uri!.port > 0)
        ? uri.port
        : (isSecure ? 443 : 80);
    final port = portNum.toString();

    // Strict IPv4 loopback (127.0.0.0/8), IPv6 loopback, and 0.0.0.0 validation (H-1)
    final isLocal = host == 'localhost' ||
        host == '::1' ||
        host.startsWith('127.') ||
        host == '0.0.0.0';

    // Strict RFC 1918 private subnets, mDNS (.local/.lan), and private IPv6 validation (H-1)
    final isLan = !isLocal &&
        (RegExp(r'^192\.168\.\d{1,3}\.\d{1,3}$').hasMatch(host) ||
            RegExp(r'^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host) ||
            RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}$').hasMatch(host) ||
            host.endsWith('.local') ||
            host.endsWith('.lan') ||
            host.startsWith('fe80:') ||
            host.startsWith('fc00:') ||
            host.startsWith('fd'));

    return NetworkTargetInfo(
      host: host,
      port: port,
      isLocalhost: isLocal,
      isPrivateLan: isLan,
      isSecure: isSecure,
    );
  }
}

class TtsDiagnosticReport {
  final TtsDiagnosticScenario scenario;
  final NetworkTargetInfo targetInfo;
  final List<TtsDiagnosticSuggestion> suggestions;
  final String rawError;
  final int? statusCode;
  final int timeoutSeconds;

  const TtsDiagnosticReport({
    required this.scenario,
    required this.targetInfo,
    required this.suggestions,
    required this.rawError,
    this.statusCode,
    this.timeoutSeconds = 30,
  });
}

class TtsDiagnosticAnalyzer {
  static TtsDiagnosticReport analyze(Object error,
      {String? configuredUrl, Duration? timeout}) {
    final rawError = error.toString();
    final targetInfo = NetworkTargetInfo.fromUrl(configuredUrl);
    final seconds = timeout?.inSeconds ?? 30;

    final lower = rawError.toLowerCase();

    // 1. Timeout scenario
    if (lower.contains('timeoutexception') ||
        lower.contains('timed out') ||
        lower.contains('deadline exceeded')) {
      return TtsDiagnosticReport(
        scenario: TtsDiagnosticScenario.timeout,
        targetInfo: targetInfo,
        suggestions: const [TtsDiagnosticSuggestion.checkGpuTimeout],
        rawError: rawError,
        timeoutSeconds: seconds,
      );
    }

    // 2. Authentication failure scenario
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized')) {
      return TtsDiagnosticReport(
        scenario: TtsDiagnosticScenario.authFailed,
        targetInfo: targetInfo,
        suggestions: const [TtsDiagnosticSuggestion.checkApiKey],
        rawError: rawError,
        statusCode: lower.contains('401') ? 401 : 403,
      );
    }

    // 3. Endpoint Not Found scenario (404)
    if (lower.contains('404') || lower.contains('not found')) {
      return TtsDiagnosticReport(
        scenario: TtsDiagnosticScenario.notFound,
        targetInfo: targetInfo,
        suggestions: const [TtsDiagnosticSuggestion.checkEndpointPath],
        rawError: rawError,
        statusCode: 404,
      );
    }

    // 4. Unreachable scenario (502, 503, 504, 10061, SocketException, ClientException)
    if (lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('connection refused') ||
        lower.contains('10061') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed to connect')) {
      final suggestions = <TtsDiagnosticSuggestion>[
        TtsDiagnosticSuggestion.checkServerRunning,
        TtsDiagnosticSuggestion.checkPort,
      ];

      if (targetInfo.isLocalhost) {
        suggestions.add(TtsDiagnosticSuggestion.proxyLoopback);
      } else if (targetInfo.isPrivateLan) {
        suggestions.add(TtsDiagnosticSuggestion.lanWifiFirewall);
      } else {
        suggestions.add(TtsDiagnosticSuggestion.publicDns);
      }

      int? code;
      if (lower.contains('502')) {
        code = 502;
      } else if (lower.contains('503')) {
        code = 503;
      } else if (lower.contains('504')) {
        code = 504;
      }

      return TtsDiagnosticReport(
        scenario: TtsDiagnosticScenario.unreachable,
        targetInfo: targetInfo,
        suggestions: suggestions,
        rawError: rawError,
        statusCode: code,
      );
    }

    // 5. Generic/Unknown error
    return TtsDiagnosticReport(
      scenario: TtsDiagnosticScenario.unknown,
      targetInfo: targetInfo,
      suggestions: const [TtsDiagnosticSuggestion.genericError],
      rawError: rawError,
    );
  }
}
