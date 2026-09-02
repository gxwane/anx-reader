import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/offline_sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  group('OfflineSyncQueue Unit Tests', () {
    test('enqueues book IDs, removes duplicates, and persists correctly', () async {
      expect(OfflineSyncQueue.getPendingBookIds(), isEmpty);

      await OfflineSyncQueue.addPendingBook(101);
      await OfflineSyncQueue.addPendingBook(102);
      await OfflineSyncQueue.addPendingBook(101); // Duplicate

      final pending = OfflineSyncQueue.getPendingBookIds();
      expect(pending.length, 2);
      expect(pending.contains(101), isTrue);
      expect(pending.contains(102), isTrue);
    });

    test('removes specific book ID from queue and leaves others intact', () async {
      await OfflineSyncQueue.addPendingBook(201);
      await OfflineSyncQueue.addPendingBook(202);
      await OfflineSyncQueue.addPendingBook(203);

      await OfflineSyncQueue.removePendingBook(202);

      final pending = OfflineSyncQueue.getPendingBookIds();
      expect(pending.length, 2);
      expect(pending.contains(201), isTrue);
      expect(pending.contains(202), isFalse);
      expect(pending.contains(203), isTrue);
    });

    test('clears entire queue atomically', () async {
      await OfflineSyncQueue.addPendingBook(301);
      await OfflineSyncQueue.addPendingBook(302);
      expect(OfflineSyncQueue.getPendingBookIds().length, 2);

      await OfflineSyncQueue.clear();
      expect(OfflineSyncQueue.getPendingBookIds(), isEmpty);
    });

    test('handles concurrent async writes without data loss', () async {
      final futures = <Future<void>>[];
      for (int i = 1; i <= 50; i++) {
        futures.add(OfflineSyncQueue.addPendingBook(i));
      }
      await Future.wait(futures);

      final pending = OfflineSyncQueue.getPendingBookIds();
      expect(pending.length, 50);
      for (int i = 1; i <= 50; i++) {
        expect(pending.contains(i), isTrue);
      }
    });
  });
}
