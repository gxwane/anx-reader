import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/sync/book_progress_payload.dart';

void main() {
  group('Bookshelf Progress Index Aggregation Tests', () {
    test('serializes and deserializes multi-book index dictionary', () {
      final time1 = DateTime.utc(2026, 9, 2, 10, 0, 0);
      final time2 = DateTime.utc(2026, 9, 2, 11, 30, 0);

      final indexMap = <String, BookProgressPayload>{
        'md5_001': BookProgressPayload(
          fileMd5: 'md5_001',
          lastReadPosition: 'epubcfi(/6/2!/4/10)',
          readingPercentage: 0.25,
          readingStatus: 'reading',
          updatedAt: time1,
          deviceName: 'Phone',
        ),
        'md5_002': BookProgressPayload(
          fileMd5: 'md5_002',
          lastReadPosition: 'epubcfi(/6/8!/4/50)',
          readingPercentage: 1.0,
          readingStatus: 'finished',
          updatedAt: time2,
          deviceName: 'Desktop',
        ),
      };

      final jsonMap = indexMap.map((k, v) => MapEntry(k, v.toJson()));
      expect(jsonMap.length, 2);
      expect(jsonMap['md5_001']?['reading_percentage'], 0.25);
      expect(jsonMap['md5_002']?['reading_status'], 'finished');

      // Reconstruct
      final reconstructed = <String, BookProgressPayload>{};
      for (final entry in jsonMap.entries) {
        reconstructed[entry.key] = BookProgressPayload.fromJson(entry.value);
      }

      expect(reconstructed.length, 2);
      expect(reconstructed['md5_001']?.lastReadPosition, 'epubcfi(/6/2!/4/10)');
      expect(reconstructed['md5_002']?.readingPercentage, 1.0);
      expect(reconstructed['md5_002']?.updatedAt, time2);
    });

    test('incremental merge respects latest timestamp per book', () {
      final t1 = DateTime.utc(2026, 9, 2, 10, 0, 0);
      final t2 = DateTime.utc(2026, 9, 2, 12, 0, 0);
      final tEarlier = DateTime.utc(2026, 9, 2, 9, 0, 0);

      final existingIndex = <String, BookProgressPayload>{
        'md5_A': BookProgressPayload(
          fileMd5: 'md5_A',
          lastReadPosition: 'pos_1',
          readingPercentage: 0.1,
          readingStatus: 'reading',
          updatedAt: t1,
          deviceName: 'Device A',
        ),
      };

      // Scenario 1: incoming payload for md5_A is newer -> updates
      final newerPayload = BookProgressPayload(
        fileMd5: 'md5_A',
        lastReadPosition: 'pos_2',
        readingPercentage: 0.4,
        readingStatus: 'reading',
        updatedAt: t2,
        deviceName: 'Device B',
      );

      if (existingIndex['md5_A'] == null ||
          newerPayload.updatedAt.isAfter(existingIndex['md5_A']!.updatedAt)) {
        existingIndex['md5_A'] = newerPayload;
      }

      expect(existingIndex['md5_A']?.readingPercentage, 0.4);
      expect(existingIndex['md5_A']?.deviceName, 'Device B');

      // Scenario 2: incoming payload for md5_A is older -> ignored
      final olderPayload = BookProgressPayload(
        fileMd5: 'md5_A',
        lastReadPosition: 'pos_old',
        readingPercentage: 0.05,
        readingStatus: 'reading',
        updatedAt: tEarlier,
        deviceName: 'Device C',
      );

      if (existingIndex['md5_A'] == null ||
          olderPayload.updatedAt.isAfter(existingIndex['md5_A']!.updatedAt)) {
        existingIndex['md5_A'] = olderPayload;
      }

      expect(existingIndex['md5_A']?.readingPercentage, 0.4); // Preserved
      expect(existingIndex['md5_A']?.deviceName, 'Device B');

      // Scenario 3: incoming payload for new book md5_B -> added
      final newBookPayload = BookProgressPayload(
        fileMd5: 'md5_B',
        lastReadPosition: 'pos_B1',
        readingPercentage: 0.8,
        readingStatus: 'reading',
        updatedAt: t1,
        deviceName: 'Device A',
      );

      if (existingIndex['md5_B'] == null ||
          newBookPayload.updatedAt.isAfter(existingIndex['md5_B']!.updatedAt)) {
        existingIndex['md5_B'] = newBookPayload;
      }

      expect(existingIndex.length, 2);
      expect(existingIndex['md5_B']?.readingPercentage, 0.8);
    });

    test('correctly converts reading_status string names to SQLite enum values', () {
      expect(
        ReadingStatus.values
            .firstWhere(
              (e) => e.name == 'reading',
              orElse: () => ReadingStatus.unread,
            )
            .value,
        ReadingStatus.reading.value,
      );

      expect(
        ReadingStatus.values
            .firstWhere(
              (e) => e.name == 'finished',
              orElse: () => ReadingStatus.unread,
            )
            .value,
        ReadingStatus.finished.value,
      );

      expect(
        ReadingStatus.values
            .firstWhere(
              (e) => e.name == 'unknown_status',
              orElse: () => ReadingStatus.unread,
            )
            .value,
        ReadingStatus.unread.value,
      );
    });

    test('BookNoteDao dirty tracking marks, checks, and cleans dirty state correctly', () {
      BookNoteDao.clearAllDirty();
      expect(BookNoteDao.isDirty(101), false);
      expect(BookNoteDao.isDirty(102), false);

      // Mark dirty
      BookNoteDao.markDirty(101);
      expect(BookNoteDao.isDirty(101), true);
      expect(BookNoteDao.isDirty(102), false);

      // Clean
      BookNoteDao.markClean(101);
      expect(BookNoteDao.isDirty(101), false);

      // Clear all
      BookNoteDao.markDirty(101);
      BookNoteDao.markDirty(102);
      expect(BookNoteDao.isDirty(101), true);
      expect(BookNoteDao.isDirty(102), true);
      BookNoteDao.clearAllDirty();
      expect(BookNoteDao.isDirty(101), false);
      expect(BookNoteDao.isDirty(102), false);
    });
  });
}
