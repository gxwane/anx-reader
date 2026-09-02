import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:synchronized/synchronized.dart';

/// Thread-safe persistent queue for tracking books that have pending micro-sync
/// updates (progress/notes) that failed due to offline/weak network conditions.
class OfflineSyncQueue {
  static const String _key = 'pending_sync_book_ids';
  static final Lock _lock = Lock();

  /// Retrieves the current set of pending book IDs.
  static Set<int> getPendingBookIds() {
    try {
      final list = Prefs().prefs.getStringList(_key) ?? [];
      return list.map(int.tryParse).whereType<int>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Thread-safely enqueues a book ID for deferred synchronization.
  static Future<void> addPendingBook(int bookId) async {
    await _lock.synchronized(() async {
      try {
        final current = getPendingBookIds();
        if (current.add(bookId)) {
          await Prefs().prefs.setStringList(
                _key,
                current.map((id) => id.toString()).toList(),
              );
        }
      } catch (_) {}
    });
  }

  /// Thread-safely removes a book ID once synchronization succeeds.
  static Future<void> removePendingBook(int bookId) async {
    await _lock.synchronized(() async {
      try {
        final current = getPendingBookIds();
        if (current.remove(bookId)) {
          await Prefs().prefs.setStringList(
                _key,
                current.map((id) => id.toString()).toList(),
              );
        }
      } catch (_) {}
    });
  }

  /// Thread-safely clears the entire queue.
  static Future<void> clear() async {
    await _lock.synchronized(() async {
      try {
        await Prefs().prefs.remove(_key);
      } catch (_) {}
    });
  }
}
