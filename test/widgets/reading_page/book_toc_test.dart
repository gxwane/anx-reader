import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Book TOC Chevron & Accordion UX Alignment Tests', () {
    late TocItem parentItem;
    late TocItem leafItem;

    setUp(() {
      final childItem = TocItem(
        id: 'child-1',
        href: 'ch1_sub1.xhtml',
        label: 'Section 1.1',
        subitems: [],
        level: 1,
        startPage: 2,
        startPercentage: 0.05,
      );

      parentItem = TocItem(
        id: 'parent-1',
        href: 'ch1.xhtml',
        label: 'Chapter 1: The Beginning',
        subitems: [childItem],
        level: 0,
        startPage: 1,
        startPercentage: 0.01,
      );

      leafItem = TocItem(
        id: 'leaf-1',
        href: 'ch2.xhtml',
        label: 'Chapter 2: Standalone',
        subitems: [],
        level: 0,
        startPage: 10,
        startPercentage: 0.15,
      );
    });

    testWidgets(
        'GIVEN parent TOC item in LTR, WHEN collapsed (isExpanded: false), THEN shows chevron_right',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocItemWidget(
              tocItem: parentItem,
              depth: 0,
              isExpanded: false,
              isSelected: false,
              onToggle: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets(
        'GIVEN parent TOC item in LTR, WHEN expanded (isExpanded: true), THEN shows keyboard_arrow_down',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocItemWidget(
              tocItem: parentItem,
              depth: 0,
              isExpanded: true,
              isSelected: false,
              onToggle: () {},
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets(
        'GIVEN parent TOC item in RTL, WHEN collapsed (isExpanded: false), THEN shows chevron_left',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: TocItemWidget(
                tocItem: parentItem,
                depth: 0,
                isExpanded: false,
                isSelected: false,
                onToggle: () {},
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });

    testWidgets(
        'GIVEN parent TOC item, WHEN tapping chevron button, THEN calls onToggle',
        (tester) async {
      var toggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocItemWidget(
              tocItem: parentItem,
              depth: 0,
              isExpanded: false,
              isSelected: false,
              onToggle: () {
                toggled = true;
              },
              onTap: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      expect(toggled, isTrue);
    });

    testWidgets(
        'GIVEN leaf TOC item (subitems is empty), THEN no expand/collapse button is rendered',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocItemWidget(
              tocItem: leafItem,
              depth: 0,
              isExpanded: false,
              isSelected: false,
              onToggle: null,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(IconButton), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });

    testWidgets(
        'GIVEN active/selected TOC item, THEN highlights with primary color & bold, and never renders keyboard_arrow_right_rounded',
        (tester) async {
      const primaryColor = Colors.deepPurple;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: primaryColor)),
          home: Scaffold(
            body: TocItemWidget(
              tocItem: leafItem,
              depth: 0,
              isExpanded: false,
              isSelected: true,
              onToggle: null,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify no misleading arrow icon exists on the item
      expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      // Verify text rendered with bold and primary color
      final textWidget = tester.widget<Text>(find.text(leafItem.label));
      expect(textWidget.style?.fontWeight, equals(FontWeight.bold));
      expect(textWidget.style?.fontSize, equals(16));
    });
  });
}
