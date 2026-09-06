import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'eInkMode': false,
      'openBookAnimation': true,
      'pageTurnStyle': 'slide',
    });
    await Prefs().initPrefs();
  });

  group('E-ink Anti-Flicker & Zero-Animation Spec Tests', () {
    testWidgets('GIVEN eInkMode is true, WHEN building theme, THEN uses NoAnimationPageTransitionsBuilder for all platforms',
        (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            Prefs().eInkMode = true;
            final theme = colorSchema(Prefs(), context, Brightness.light);

            for (final platform in TargetPlatform.values) {
              final builder = theme.pageTransitionsTheme.builders[platform];
              expect(builder, isA<NoAnimationPageTransitionsBuilder>(),
                  reason: 'Platform $platform should use NoAnimationPageTransitionsBuilder');

              // Verify buildTransitions returns child directly
              final childWidget = Container(key: const ValueKey('test-child'));
              final mockRoute = MaterialPageRoute<void>(builder: (_) => childWidget);
              final result = builder!.buildTransitions<void>(
                mockRoute,
                context,
                kAlwaysDismissedAnimation,
                kAlwaysDismissedAnimation,
                childWidget,
              );
              expect(result, same(childWidget),
                  reason: 'buildTransitions must return child directly without animation wrappers');
            }

            return Container();
          },
        ),
      );
    });

    testWidgets('GIVEN eInkMode is false, WHEN building theme, THEN uses standard animated transitions',
        (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            Prefs().eInkMode = false;
            final theme = colorSchema(Prefs(), context, Brightness.light);

            final androidBuilder = theme.pageTransitionsTheme.builders[TargetPlatform.android];
            expect(androidBuilder, isNot(isA<NoAnimationPageTransitionsBuilder>()));

            return Container();
          },
        ),
      );
    });

    test('GIVEN eInkMode is true, WHEN accessing openBookAnimation, THEN always evaluates to false', () {
      Prefs().eInkMode = false;
      Prefs().openBookAnimation = true;
      expect(Prefs().openBookAnimation, isTrue);

      Prefs().eInkMode = true;
      expect(Prefs().openBookAnimation, isFalse,
          reason: 'openBookAnimation must short-circuit to false when eInkMode is active');

      Prefs().eInkMode = false;
      expect(Prefs().openBookAnimation, isTrue,
          reason: 'openBookAnimation must restore original user preference when eInkMode is deactivated');
    });

    test('GIVEN eInkMode is true and user selected slide, WHEN accessing pageTurnStyle, THEN falls back to noAnimation', () {
      Prefs().eInkMode = false;
      Prefs().pageTurnStyle = PageTurn.slide;
      expect(Prefs().pageTurnStyle, equals(PageTurn.slide));

      Prefs().eInkMode = true;
      expect(Prefs().pageTurnStyle, equals(PageTurn.noAnimation),
          reason: 'pageTurnStyle must fall back to noAnimation when eInkMode is active');

      Prefs().eInkMode = false;
      expect(Prefs().pageTurnStyle, equals(PageTurn.slide),
          reason: 'pageTurnStyle must restore slide when eInkMode is turned off');
    });

    test('GIVEN eInkMode is toggled, WHEN calling applySmartDialogEinkMode, THEN updates SmartDialog animation configs', () {
      applySmartDialogEinkMode(true);
      expect(SmartDialog.config.custom.useAnimation, isFalse);
      expect(SmartDialog.config.attach.useAnimation, isFalse);
      expect(SmartDialog.config.toast.useAnimation, isFalse);
      expect(SmartDialog.config.loading.useAnimation, isFalse);

      applySmartDialogEinkMode(false);
      expect(SmartDialog.config.custom.useAnimation, isTrue);
      expect(SmartDialog.config.attach.useAnimation, isTrue);
      expect(SmartDialog.config.toast.useAnimation, isTrue);
      expect(SmartDialog.config.loading.useAnimation, isTrue);
    });

    testWidgets('GIVEN HeroMode is disabled at root, WHEN rendering Hero, THEN hero mode is disabled',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => HeroMode(
            enabled: false,
            child: child!,
          ),
          home: const Scaffold(
            body: Hero(
              tag: 'test-hero',
              child: Text('Hero Content'),
            ),
          ),
        ),
      );

      expect(find.text('Hero Content'), findsOneWidget);
      expect(tester.widget<HeroMode>(find.byType(HeroMode)).enabled, isFalse);
    });

    testWidgets('GIVEN eInkMode is true, WHEN building pageTurnStyle DropdownMenu, THEN slide entry is disabled',
        (tester) async {
      Prefs().eInkMode = true;
      final entries = PageTurn.values
          .map((e) => DropdownMenuEntry(
                value: e,
                label: e.name,
                enabled: !(Prefs().eInkMode && e == PageTurn.slide),
              ))
          .toList();

      final slideEntry = entries.firstWhere((e) => e.value == PageTurn.slide);
      final noAnimEntry = entries.firstWhere((e) => e.value == PageTurn.noAnimation);

      expect(slideEntry.enabled, isFalse);
      expect(noAnimEntry.enabled, isTrue);
    });
  });
}
