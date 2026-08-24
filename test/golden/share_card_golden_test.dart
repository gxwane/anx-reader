import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/widgets/book_share/excerpt_share_card.dart';
import 'package:anx_reader/enums/excerpt_share_template.dart';
import 'package:anx_reader/models/font_model.dart';
import 'golden_test_helper.dart';

const _bookTitle = '存在主义心理治疗';
const _author = '欧文·亚隆';
const _excerpt = '人是被判决为自由的。一旦被抛入世界，他便对自己做的一切负责。';
const _chapter = '第三章 自由';
const _textColor = Color(0xFF2C2C2E);
const _bgColor = Colors.white;

FontModel get _font => FontModel(
  label: 'Source Han Serif',
  name: 'SourceHanSerifSC-Regular',
  path: 'assets/fonts/SourceHanSerifSC-Regular.otf',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupGoldenComparator(Uri.parse('test/golden/share_card_golden_test.dart'), tolerance: 0.01);
    await loadGoldenTestFonts();
  });

  Future<void> buildCard(WidgetTester tester, ExcerptShareTemplateEnum template) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF0F0F0),
        body: Center(
          child: ExcerptShareCard(
            bookTitle: _bookTitle, author: _author,
            excerpt: _excerpt, chapter: _chapter,
            template: template, font: _font,
            textColor: _textColor, backgroundColor: _bgColor,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('share card watermark - defaultTemplate', (tester) async {
    await buildCard(tester, ExcerptShareTemplateEnum.defaultTemplate);
    await expectLater(find.byType(ExcerptShareCard), matchesGoldenFile('goldens/share_card_defaultTemplate.png'));
  });

  testWidgets('share card watermark - simpleTemplate', (tester) async {
    await buildCard(tester, ExcerptShareTemplateEnum.simpleTemplate);
    await expectLater(find.byType(ExcerptShareCard), matchesGoldenFile('goldens/share_card_simpleTemplate.png'));
  });

  testWidgets('share card watermark - elegantTemplate', (tester) async {
    await buildCard(tester, ExcerptShareTemplateEnum.elegantTemplate);
    await expectLater(find.byType(ExcerptShareCard), matchesGoldenFile('goldens/share_card_elegantTemplate.png'));
  });

  testWidgets('share card watermark - verticalTemplate', (tester) async {
    await buildCard(tester, ExcerptShareTemplateEnum.verticalTemplate);
    await expectLater(find.byType(ExcerptShareCard), matchesGoldenFile('goldens/share_card_verticalTemplate.png'));
  });
}