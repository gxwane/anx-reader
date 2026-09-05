import 'dart:async';

import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Common interface for any controller that supports pausing and resuming.
abstract class PausableWebViewController {
  Future<void> pause();
  Future<void> resume();
}

/// Adapter converting [InAppWebViewController] to [PausableWebViewController].
class InAppWebViewAdapter implements PausableWebViewController {
  final InAppWebViewController controller;

  InAppWebViewAdapter(this.controller);

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> resume() => controller.resume();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InAppWebViewAdapter &&
          runtimeType == other.runtimeType &&
          controller == other.controller;

  @override
  int get hashCode => controller.hashCode;
}

/// Central registry that manages active WebView controllers on desktop/mobile,
/// allowing coordinated pause/resume on window state transitions (minimize, restore, etc.).
class ActiveWebViewRegistry {
  ActiveWebViewRegistry._();

  static final ActiveWebViewRegistry _instance = ActiveWebViewRegistry._();

  /// Shared singleton instance.
  factory ActiveWebViewRegistry() => _instance;

  /// Visible for testing to create isolated registry instances.
  @visibleForTesting
  factory ActiveWebViewRegistry.createInstanceForTesting() =>
      ActiveWebViewRegistry._();

  final Set<PausableWebViewController> _controllers = {};
  bool _isPaused = false;

  /// Whether active WebViews are currently paused.
  bool get isPaused => _isPaused;

  /// Current number of registered active WebViews.
  int get activeCount => _controllers.length;

  /// Registers a [PausableWebViewController].
  /// If the registry is currently paused, the newly registered controller is immediately paused.
  void register(PausableWebViewController controller) {
    _controllers.add(controller);
    if (_isPaused) {
      _safelyPauseController(controller);
    }
  }

  /// Unregisters a [PausableWebViewController].
  void unregister(PausableWebViewController controller) {
    _controllers.remove(controller);
  }

  /// Convenience method to register an [InAppWebViewController].
  void registerInAppWebView(InAppWebViewController controller) {
    register(InAppWebViewAdapter(controller));
  }

  /// Convenience method to unregister an [InAppWebViewController].
  void unregisterInAppWebView(InAppWebViewController controller) {
    unregister(InAppWebViewAdapter(controller));
  }

  /// Pauses all registered WebViews (idempotent).
  Future<void> pauseAll() async {
    if (_isPaused) {
      return;
    }
    _isPaused = true;
    for (final controller in _controllers.toList()) {
      await _safelyPauseController(controller);
    }
  }

  /// Resumes all registered WebViews (idempotent).
  Future<void> resumeAll() async {
    if (!_isPaused) {
      return;
    }
    _isPaused = false;
    for (final controller in _controllers.toList()) {
      await _safelyResumeController(controller);
    }
  }

  Future<void> _safelyPauseController(
    PausableWebViewController controller,
  ) async {
    try {
      await controller.pause();
    } catch (e, stackTrace) {
      AnxLog.warning(
        'ActiveWebViewRegistry: failed to pause controller: $e',
        stackTrace,
      );
    }
  }

  Future<void> _safelyResumeController(
    PausableWebViewController controller,
  ) async {
    try {
      await controller.resume();
    } catch (e, stackTrace) {
      AnxLog.warning(
        'ActiveWebViewRegistry: failed to resume controller: $e',
        stackTrace,
      );
    }
  }
}
