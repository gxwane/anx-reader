import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/widgets/common/app_scrollbar.dart';

void main() {
  group('AppScrollbar Widget Tests', () {
    testWidgets('renders without throwing when ScrollController is unattached', (tester) async {
      final unattachedController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppScrollbar(
              controller: unattachedController,
              thumbVisibility: true,
              child: Container(height: 200, width: 200, color: Colors.blue),
            ),
          ),
        ),
      );

      // No exception should be thrown even with thumbVisibility: true
      expect(find.byType(AppScrollbar), findsOneWidget);
    });

    testWidgets('renders properly with attached ListView', (tester) async {
      final controller = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppScrollbar(
              controller: controller,
              child: ListView.builder(
                controller: controller,
                itemCount: 50,
                itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppScrollbar), findsOneWidget);
      expect(find.text('Item 0'), findsOneWidget);
    });

    testWidgets('on Windows desktop: handles mouse hover with null controller without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: AppScrollbar(
              child: Container(height: 200, width: 200, color: Colors.blue),
            ),
          ),
        ),
      );

      expect(find.byType(AppScrollbar), findsOneWidget);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(AppScrollbar)));
      await tester.pumpAndSettle();

      // Successfully hovered without triggering "no ScrollPosition attached"
      expect(find.byType(AppScrollbar), findsOneWidget);
    });

    testWidgets('on Windows desktop: dragging scrollbar thumb scrolls attached view', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: AppScrollbar(
              controller: controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: controller,
                itemCount: 100,
                itemExtent: 50.0,
                itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(controller.offset, 0.0);

      // In default 800x600 test window, scrollbar thumb is at right edge ~797, 45
      final dragScrollbarGesture = await tester.startGesture(const Offset(797.0, 45.0));
      await tester.pumpAndSettle();
      await dragScrollbarGesture.moveBy(const Offset(0.0, 100.0));
      await tester.pumpAndSettle();
      await dragScrollbarGesture.up();
      await tester.pumpAndSettle();

      // Controller offset must have scrolled down
      expect(controller.offset, greaterThan(0.0));
    });
  });
}
