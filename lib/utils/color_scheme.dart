import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

ThemeData colorSchema(
  Prefs prefsNotifier,
  BuildContext context,
  Brightness brightness,
) {
  brightness = prefsNotifier.eInkMode
      ? Brightness.light
      : switch (prefsNotifier.themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
  Color seedColor = prefsNotifier.themeColor;
  final isDark = brightness == Brightness.dark;
  final isEinkMode = prefsNotifier.eInkMode;

  final lightGropedBackground = const Color(0xFFF2F2F7);
  final darkGropedBackground =
      prefsNotifier.trueDarkMode ? Color(0xFF000000) : Color(0xFF1C1C1E);
  final gropedBackgroundColor = isEinkMode
      ? Colors.white
      : isDark
          ? darkGropedBackground
          : lightGropedBackground;

  final colorScheme = isEinkMode
      ? const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          primaryContainer: Colors.grey,
          onPrimaryContainer: Colors.black,
          secondary: Colors.grey,
          onSecondary: Colors.white,
          secondaryContainer: Colors.black12,
          onSecondaryContainer: Colors.black,
          surface: Colors.white,
          onSurface: Colors.black,
        )
      : switch (brightness) {
          Brightness.light => ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
              surfaceContainer: Color(0xFFFFFFFF),
              surface: lightGropedBackground,
            ),
          Brightness.dark => ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.dark,
              surfaceContainer: Color(0xFF2C2C2E),
              surface: darkGropedBackground,
            ),
        };

  ThemeData themeData = isEinkMode
      ? FlexThemeData.light(
          useMaterial3: true,
          swapLegacyOnMaterial3: true,
          colorScheme: colorScheme)
      : switch (brightness) {
          Brightness.light => FlexThemeData.light(
              useMaterial3: true,
              swapLegacyOnMaterial3: true,
              colorScheme: colorScheme,
            ),
          Brightness.dark => FlexThemeData.dark(
              useMaterial3: true,
              swapLegacyOnMaterial3: true,
              darkIsTrueBlack: prefsNotifier.trueDarkMode,
              colorScheme: colorScheme,
            )
        };

  return themeData
      .copyWith(
          scrollbarTheme: ScrollbarThemeData(
            interactive: true,
            thickness: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.dragged)) {
                return 8.0;
              }
              return 6.0;
            }),
            radius: const Radius.circular(4.0),
            crossAxisMargin: 2.0,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              final scheme = themeData.colorScheme;
              if (isEinkMode) {
                return scheme.onSurface;
              }
              if (states.contains(WidgetState.dragged)) {
                return scheme.primary.withValues(alpha: 0.85);
              }
              if (states.contains(WidgetState.hovered)) {
                return scheme.onSurface.withValues(alpha: 0.50);
              }
              return scheme.onSurface.withValues(alpha: 0.25);
            }),
          ),
          sliderTheme: const SliderThemeData(year2023: false),
          progressIndicatorTheme:
              const ProgressIndicatorThemeData(year2023: false),
          scaffoldBackgroundColor: gropedBackgroundColor,
          bottomSheetTheme: BottomSheetThemeData()
              .copyWith(backgroundColor: gropedBackgroundColor),
          drawerTheme: DrawerThemeData()
              .copyWith(backgroundColor: gropedBackgroundColor),
          dialogTheme: DialogThemeData()
              .copyWith(backgroundColor: gropedBackgroundColor))
      .useSystemChineseFont(brightness);
}
