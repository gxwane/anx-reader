import 'package:anx_reader/utils/webView/active_webview_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePausableController implements PausableWebViewController {
  int pauseCount = 0;
  int resumeCount = 0;
  bool shouldThrowOnPause = false;
  bool shouldThrowOnResume = false;

  @override
  Future<void> pause() async {
    if (shouldThrowOnPause) {
      throw Exception('Simulated pause failure');
    }
    pauseCount++;
  }

  @override
  Future<void> resume() async {
    if (shouldThrowOnResume) {
      throw Exception('Simulated resume failure');
    }
    resumeCount++;
  }
}

void main() {
  late ActiveWebViewRegistry registry;

  setUp(() {
    registry = ActiveWebViewRegistry.createInstanceForTesting();
  });

  group('ActiveWebViewRegistry Tests', () {
    test('register and unregister track controllers correctly', () {
      final controller = FakePausableController();

      expect(registry.activeCount, 0);
      registry.register(controller);
      expect(registry.activeCount, 1);

      registry.unregister(controller);
      expect(registry.activeCount, 0);
    });

    test('pauseAll pauses all registered controllers', () async {
      final c1 = FakePausableController();
      final c2 = FakePausableController();

      registry.register(c1);
      registry.register(c2);

      await registry.pauseAll();

      expect(c1.pauseCount, 1);
      expect(c2.pauseCount, 1);
      expect(registry.isPaused, isTrue);
    });

    test('resumeAll resumes all registered controllers', () async {
      final c1 = FakePausableController();
      final c2 = FakePausableController();

      registry.register(c1);
      registry.register(c2);

      await registry.pauseAll();
      await registry.resumeAll();

      expect(c1.resumeCount, 1);
      expect(c2.resumeCount, 1);
      expect(registry.isPaused, isFalse);
    });

    test('pauseAll and resumeAll are idempotent', () async {
      final c = FakePausableController();
      registry.register(c);

      await registry.pauseAll();
      await registry.pauseAll();
      expect(c.pauseCount, 1);

      await registry.resumeAll();
      await registry.resumeAll();
      expect(c.resumeCount, 1);
    });

    test('new controller registered while paused is immediately paused', () async {
      await registry.pauseAll();
      expect(registry.isPaused, isTrue);

      final c = FakePausableController();
      registry.register(c);

      expect(c.pauseCount, 1);
    });

    test('controller failure does not block other controllers during pauseAll', () async {
      final faulty = FakePausableController()..shouldThrowOnPause = true;
      final healthy = FakePausableController();

      registry.register(faulty);
      registry.register(healthy);

      await registry.pauseAll();

      expect(faulty.pauseCount, 0);
      expect(healthy.pauseCount, 1);
      expect(registry.isPaused, isTrue);
    });

    test('controller failure does not block other controllers during resumeAll', () async {
      final faulty = FakePausableController()..shouldThrowOnResume = true;
      final healthy = FakePausableController();

      registry.register(faulty);
      registry.register(healthy);

      await registry.pauseAll();
      await registry.resumeAll();

      expect(healthy.resumeCount, 1);
      expect(registry.isPaused, isFalse);
    });

    test('unregistered controller is not paused or resumed', () async {
      final c1 = FakePausableController();
      final c2 = FakePausableController();

      registry.register(c1);
      registry.register(c2);
      registry.unregister(c2);

      await registry.pauseAll();
      expect(c1.pauseCount, 1);
      expect(c2.pauseCount, 0);

      await registry.resumeAll();
      expect(c1.resumeCount, 1);
      expect(c2.resumeCount, 0);
    });
  });
}
