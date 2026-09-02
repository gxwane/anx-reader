import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/service/sync/sync_local_change_detector.dart';

void main() {
  group('SyncLocalChangeDetector.hasLocalChangedSinceLastSync', () {
    // Gate 1 Scenario 3: null lastSyncedLocalDbTime → 视为有改动
    test('returns true when lastSyncedLocalDbTime is null (first sync)', () {
      final current = DateTime(2024, 1, 1, 12, 0, 10);
      expect(
        SyncLocalChangeDetector.hasLocalChangedSinceLastSync(
          currentLocalTime: current,
          lastSyncedLocalDbTime: null,
        ),
        isTrue,
      );
    });

    // Gate 1 Scenario 1: 下载后本地未改动 → 跳过
    test('returns false when currentLocalTime equals lastSyncedLocalDbTime', () {
      final t = DateTime(2024, 1, 1, 12, 0, 0);
      expect(
        SyncLocalChangeDetector.hasLocalChangedSinceLastSync(
          currentLocalTime: t,
          lastSyncedLocalDbTime: t,
        ),
        isFalse,
      );
    });

    // Gate 1 Scenario 5: 1 秒后改动，无死区
    test('returns true when currentLocalTime is 1 second after lastSyncedLocalDbTime', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final current = last.add(const Duration(seconds: 1));
      expect(
        SyncLocalChangeDetector.hasLocalChangedSinceLastSync(
          currentLocalTime: current,
          lastSyncedLocalDbTime: last,
        ),
        isTrue,
      );
    });

    // Gate 1 Scenario 2: 正常读书后改动
    test('returns true when currentLocalTime is after lastSyncedLocalDbTime', () {
      final last = DateTime(2024, 1, 1, 12, 0, 0);
      final current = last.add(const Duration(minutes: 30));
      expect(
        SyncLocalChangeDetector.hasLocalChangedSinceLastSync(
          currentLocalTime: current,
          lastSyncedLocalDbTime: last,
        ),
        isTrue,
      );
    });

    // Edge: currentLocalTime 早于 lastSyncedLocalDbTime（不应发生，但安全处理）
    test('returns false when currentLocalTime is before lastSyncedLocalDbTime', () {
      final last = DateTime(2024, 1, 1, 12, 0, 10);
      final current = DateTime(2024, 1, 1, 12, 0, 0);
      expect(
        SyncLocalChangeDetector.hasLocalChangedSinceLastSync(
          currentLocalTime: current,
          lastSyncedLocalDbTime: last,
        ),
        isFalse,
      );
    });
  });
}
