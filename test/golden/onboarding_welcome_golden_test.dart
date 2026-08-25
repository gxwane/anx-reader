import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'golden_test_helper.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupGoldenComparator(Uri.parse('test/golden/onboarding_welcome_golden_test.dart'), tolerance: 0.01);
    await loadGoldenTestFonts();
  });

  testWidgets('Onboarding welcome title visual check', (tester) async {
    // Simulate a typical phone screen: 360x780 dp at 3x density
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 60.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Simulate introduction_screen title area
                Icon(Icons.book_outlined, size: 100, color: Colors.blue),
                const SizedBox(height: 40),
                Text(
                  'Welcome to\nAnx Reader GX Preview',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28.0,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Start your reading journey',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19.0,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/onboarding_welcome_title.png'),
    );
  });
}