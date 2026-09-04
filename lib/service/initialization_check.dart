import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/version_check_type.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/page/onboarding_screen.dart';
import 'package:anx_reader/page/changelog_screen.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class InitializationCheck {
  static String? _lastVersion;
  static String? _currentVersion;

  static Future<String> get lastVersion async {
    if (_lastVersion == null) {
      await _checkVersion();
    }
    return _lastVersion!;
  }

  static Future<String> get currentVersion async {
    if (_currentVersion == null) {
      await _checkVersion();
    }
    return _currentVersion!;
  }

  static Future<void> check() async {
    final result = await _checkVersion();
    AnxLog.info('Version check result: $result');
    if (result == VersionCheckType.firstLaunch) {
      _handleFirstLaunch();
    } else if (result == VersionCheckType.updated) {
      _handleUpdateAvailable();
    } else {
      _handleNormalStartup();
    }
  }

  static Future<VersionCheckType> _checkVersion() async {
    _lastVersion = Prefs().lastAppVersion;
    _currentVersion = await getAppVersion();
    if (_lastVersion == null) {
      return VersionCheckType.firstLaunch;
    } else {
      if (_lastVersion != _currentVersion) {
        return VersionCheckType.updated;
      } else {
        return VersionCheckType.normal;
      }
    }
  }

  static Future<void> _handleFirstLaunch() async {
    AnxLog.info('First launch detected, showing onboarding');
    final cv = await currentVersion;
    // wait 0.8 seconds to ensure the app is ready
    Future.delayed(const Duration(milliseconds: 800), () {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (routeContext) => Scaffold(
            body: OnboardingScreen(
              onComplete: () async {
                Prefs().lastAppVersion = cv;
                Navigator.pop(routeContext);
              },
            ),
          ),
        ),
      );
    });
  }

  static Future<void> _handleUpdateAvailable() async {
    final lv = await lastVersion;
    final cv = await currentVersion;
    AnxLog.info('Version update detected: $lv -> $cv');
    Future.delayed(const Duration(milliseconds: 800), () async {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await ChangelogScreen.show(
        context,
        lastVersion: lv,
        currentVersion: cv,
        onComplete: () {
          Prefs().lastAppVersion = cv;
        },
      );
    });
  }

  static void _handleNormalStartup() {
    AnxLog.info('Normal startup, proceeding to main app');
  }
}
