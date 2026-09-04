import 'dart:async';
import 'dart:io';

import 'package:anx_reader/service/tts/tts_diagnostic_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkTargetInfo Topology & Scheme-less Normalization Tests', () {
    test('handles null, empty, and whitespace URLs safely', () {
      final t1 = NetworkTargetInfo.fromUrl(null);
      expect(t1.host, equals('localhost'));
      expect(t1.port, equals('80'));
      expect(t1.isLocalhost, isTrue);
      expect(t1.isPrivateLan, isFalse);
      expect(t1.isSecure, isFalse);

      final t2 = NetworkTargetInfo.fromUrl('   ');
      expect(t2.host, equals('localhost'));
      expect(t2.port, equals('80'));
      expect(t2.isLocalhost, isTrue);
    });

    test('preserves host and port on scheme-less URLs (C-1 regression guard)', () {
      final t1 = NetworkTargetInfo.fromUrl('127.0.0.1:9880');
      expect(t1.host, equals('127.0.0.1'));
      expect(t1.port, equals('9880'));
      expect(t1.isLocalhost, isTrue);
      expect(t1.isPrivateLan, isFalse);

      final t2 = NetworkTargetInfo.fromUrl('192.168.1.100:50000');
      expect(t2.host, equals('192.168.1.100'));
      expect(t2.port, equals('50000'));
      expect(t2.isLocalhost, isFalse);
      expect(t2.isPrivateLan, isTrue);
    });

    test('parses full HTTP and HTTPS URLs with default and explicit ports', () {
      final t1 = NetworkTargetInfo.fromUrl('http://127.0.0.1:8000/v1/audio/speech');
      expect(t1.host, equals('127.0.0.1'));
      expect(t1.port, equals('8000'));
      expect(t1.isSecure, isFalse);
      expect(t1.isLocalhost, isTrue);

      final t2 = NetworkTargetInfo.fromUrl('https://api.openai.com/v1/audio/speech');
      expect(t2.host, equals('api.openai.com'));
      expect(t2.port, equals('443'));
      expect(t2.isSecure, isTrue);
      expect(t2.isLocalhost, isFalse);
      expect(t2.isPrivateLan, isFalse);
    });

    test('handles IPv4 loopback block (127.0.0.0/8), IPv6 loopback, and 0.0.0.0', () {
      expect(NetworkTargetInfo.fromUrl('http://127.0.0.2:8080').isLocalhost, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://127.1.2.3:8080').isLocalhost, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://[::1]:8080').isLocalhost, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://0.0.0.0:8080').isLocalhost, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://localhost:8080').isLocalhost, isTrue);
    });

    test('handles RFC 1918 private subnets and mDNS (.local/.lan) (H-1)', () {
      expect(NetworkTargetInfo.fromUrl('http://192.168.1.50:8000').isPrivateLan, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://10.0.0.15:8000').isPrivateLan, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://172.16.0.5:8000').isPrivateLan, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://172.31.255.1:8000').isPrivateLan, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://tts.local:8000').isPrivateLan, isTrue);
      expect(NetworkTargetInfo.fromUrl('http://myhome.lan:8000').isPrivateLan, isTrue);
    });

    test('does not misclassify public domains starting with 10 as private LAN (H-1)', () {
      final t = NetworkTargetInfo.fromUrl('https://10minutemail.com');
      expect(t.isLocalhost, isFalse);
      expect(t.isPrivateLan, isFalse);

      final t2 = NetworkTargetInfo.fromUrl('http://10.example.com');
      expect(t2.isLocalhost, isFalse);
      expect(t2.isPrivateLan, isFalse);
    });
  });

  group('TtsDiagnosticAnalyzer Scenario & Suggestion Mapping Tests', () {
    test('classifies TimeoutException scenario correctly', () {
      final report = TtsDiagnosticAnalyzer.analyze(
        TimeoutException('Future not completed'),
        configuredUrl: 'http://127.0.0.1:9880/v1/audio/speech',
        timeout: const Duration(seconds: 30),
      );

      expect(report.scenario, equals(TtsDiagnosticScenario.timeout));
      expect(report.timeoutSeconds, equals(30));
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.checkGpuTimeout));
    });

    test('classifies 401 and 403 authentication failures', () {
      final r1 = TtsDiagnosticAnalyzer.analyze(
        Exception('HTTP 401: Unauthorized access token'),
        configuredUrl: 'http://127.0.0.1:8000/v1/audio/speech',
      );
      expect(r1.scenario, equals(TtsDiagnosticScenario.authFailed));
      expect(r1.statusCode, equals(401));
      expect(r1.suggestions, contains(TtsDiagnosticSuggestion.checkApiKey));

      final r2 = TtsDiagnosticAnalyzer.analyze(
        Exception('HTTP 403: Forbidden'),
      );
      expect(r2.scenario, equals(TtsDiagnosticScenario.authFailed));
      expect(r2.statusCode, equals(403));
    });

    test('classifies 404 endpoint not found', () {
      final report = TtsDiagnosticAnalyzer.analyze(
        Exception('HTTP 404: Not Found'),
        configuredUrl: 'http://127.0.0.1:8000/speech',
      );
      expect(report.scenario, equals(TtsDiagnosticScenario.notFound));
      expect(report.statusCode, equals(404));
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.checkEndpointPath));
    });

    test('classifies Connection Refused on localhost with proxy loopback guidance', () {
      final report = TtsDiagnosticAnalyzer.analyze(
        const SocketException('Connection refused, errno = 10061'),
        configuredUrl: 'http://127.0.0.1:9880/v1/audio/speech',
      );
      expect(report.scenario, equals(TtsDiagnosticScenario.unreachable));
      expect(report.targetInfo.port, equals('9880'));
      expect(report.targetInfo.isLocalhost, isTrue);
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.checkServerRunning));
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.checkPort));
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.proxyLoopback));
      expect(report.suggestions, isNot(contains(TtsDiagnosticSuggestion.lanWifiFirewall)));
    });

    test('classifies 502 Bad Gateway on private LAN with LAN Wi-Fi guidance', () {
      final report = TtsDiagnosticAnalyzer.analyze(
        Exception('Self-Hosted TTS failed: 502 Bad Gateway'),
        configuredUrl: 'http://192.168.1.120:50000/v1/audio/speech',
      );
      expect(report.scenario, equals(TtsDiagnosticScenario.unreachable));
      expect(report.statusCode, equals(502));
      expect(report.targetInfo.port, equals('50000'));
      expect(report.targetInfo.isPrivateLan, isTrue);
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.checkServerRunning));
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.checkPort));
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.lanWifiFirewall));
      expect(report.suggestions, isNot(contains(TtsDiagnosticSuggestion.proxyLoopback)));
    });

    test('classifies connection error on public domain with DNS/Proxy guidance', () {
      final report = TtsDiagnosticAnalyzer.analyze(
        Exception('Failed to connect to host'),
        configuredUrl: 'https://my-cloud-tts.com/v1/audio/speech',
      );
      expect(report.scenario, equals(TtsDiagnosticScenario.unreachable));
      expect(report.targetInfo.isLocalhost, isFalse);
      expect(report.targetInfo.isPrivateLan, isFalse);
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.publicDns));
    });

    test('classifies generic/unknown exception gracefully', () {
      final report = TtsDiagnosticAnalyzer.analyze(
        FormatException('Malformed audio header bytes'),
      );
      expect(report.scenario, equals(TtsDiagnosticScenario.unknown));
      expect(report.suggestions, contains(TtsDiagnosticSuggestion.genericError));
      expect(report.rawError, contains('Malformed audio header bytes'));
    });
  });
}
