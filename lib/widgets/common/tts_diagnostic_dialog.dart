import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/tts_diagnostic_analyzer.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class TtsDiagnosticDialog extends StatefulWidget {
  final TtsDiagnosticReport report;

  const TtsDiagnosticDialog({super.key, required this.report});

  static Future<void> show(
    BuildContext context, {
    required Object error,
    String? url,
    Duration? timeout,
  }) {
    final report = TtsDiagnosticAnalyzer.analyze(
      error,
      configuredUrl: url,
      timeout: timeout,
    );
    return SmartDialog.show(
      useSystem: true,
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (dialogContext) => TtsDiagnosticDialog(report: report),
    );
  }

  @override
  State<TtsDiagnosticDialog> createState() => _TtsDiagnosticDialogState();
}

class _TtsDiagnosticDialogState extends State<TtsDiagnosticDialog> {
  bool _showTechnicalDetails = false;
  bool _copied = false;

  String _getScenarioTitle(BuildContext context, TtsDiagnosticReport report) {
    final l10n = L10n.of(context);
    switch (report.scenario) {
      case TtsDiagnosticScenario.unreachable:
        return l10n.ttsDiagConnectionFailedTitle;
      case TtsDiagnosticScenario.authFailed:
        return l10n.ttsDiagAuthFailedTitle(report.statusCode ?? 401);
      case TtsDiagnosticScenario.notFound:
        return l10n.ttsDiagNotFoundTitle;
      case TtsDiagnosticScenario.timeout:
        return l10n.ttsDiagTimeoutTitle;
      case TtsDiagnosticScenario.unknown:
        return l10n.ttsDiagUnknownTitle;
    }
  }

  String _getSuggestionText(BuildContext context,
      TtsDiagnosticSuggestion suggestion, TtsDiagnosticReport report) {
    final l10n = L10n.of(context);
    switch (suggestion) {
      case TtsDiagnosticSuggestion.checkServerRunning:
        return l10n.ttsDiagStepCheckServer;
      case TtsDiagnosticSuggestion.checkPort:
        return l10n.ttsDiagStepCheckPort(report.targetInfo.port);
      case TtsDiagnosticSuggestion.proxyLoopback:
        return l10n.ttsDiagStepProxyLoopback(report.targetInfo.host);
      case TtsDiagnosticSuggestion.lanWifiFirewall:
        return l10n.ttsDiagStepLanWifi(report.targetInfo.port);
      case TtsDiagnosticSuggestion.publicDns:
        return l10n.ttsDiagStepPublicDns;
      case TtsDiagnosticSuggestion.checkApiKey:
        return l10n.ttsDiagStepAuthKey;
      case TtsDiagnosticSuggestion.checkEndpointPath:
        return l10n.ttsDiagStepNotFound;
      case TtsDiagnosticSuggestion.checkGpuTimeout:
        return l10n.ttsDiagStepTimeout(report.timeoutSeconds);
      case TtsDiagnosticSuggestion.genericError:
        return report.rawError;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isError = widget.report.scenario == TtsDiagnosticScenario.authFailed ||
        widget.report.scenario == TtsDiagnosticScenario.unknown;
    final iconColor = isError ? theme.colorScheme.error : Colors.amber[700];

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.warning_amber_rounded,
            color: iconColor,
            size: 26,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getScenarioTitle(context, widget.report),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.ttsDiagChecklistHeader,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...widget.report.suggestions.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          _getSuggestionText(context, s, widget.report),
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  setState(() {
                    _showTechnicalDetails = !_showTechnicalDetails;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Icon(
                        _showTechnicalDetails
                            ? Icons.keyboard_arrow_down
                            : (Directionality.of(context) == TextDirection.rtl
                                ? Icons.chevron_left
                                : Icons.chevron_right),
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.ttsDiagTechnicalDetails,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showTechnicalDetails) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    widget.report.rawError,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(_copied ? Icons.check : Icons.copy, size: 14),
                    label: Text(
                        _copied ? l10n.ttsDiagCopied : l10n.ttsDiagCopyLog,
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.report.rawError));
                      setState(() {
                        _copied = true;
                      });
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _copied = false);
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AnxButton(
          onPressed: () => SmartDialog.dismiss(),
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }
}
