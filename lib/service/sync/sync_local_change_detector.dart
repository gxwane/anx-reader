/// Pure function helper for detecting local database changes since last sync.
///
/// Extracted from [Sync.syncDatabase] to enable isolated unit testing
/// and eliminate the unreliable cross-device timestamp comparison
/// that caused the WebDAV ping-pong loop bug.
class SyncLocalChangeDetector {
  SyncLocalChangeDetector._();

  /// Returns true if the local database has been modified since the last sync.
  ///
  /// Uses strict [DateTime.isAfter] comparison (no fuzzy threshold) because
  /// both timestamps originate from the same local filesystem — no clock skew
  /// between them is possible.
  ///
  /// [currentLocalTime] — latest mtime of local DB (including WAL file).
  /// [lastSyncedLocalDbTime] — mtime recorded at the end of the last sync.
  ///   Pass null on first sync (treated as "local has changed").
  static bool hasLocalChangedSinceLastSync({
    required DateTime currentLocalTime,
    required DateTime? lastSyncedLocalDbTime,
  }) {
    if (lastSyncedLocalDbTime == null) return true;
    return currentLocalTime.isAfter(lastSyncedLocalDbTime);
  }
}
