import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/service/sync/record_merger.dart';

void main() {
  group('RecordMerger Unit Tests (Pure Functional Core)', () {
    test('mergeBookRecords merges books by file_md5 and chooses latest state', () {
      final t0 = DateTime.utc(2026, 9, 1, 10, 0, 0);
      final t1 = DateTime.utc(2026, 9, 2, 10, 0, 0);

      final localBooks = [
        {
          'id': 1,
          'title': 'Three Body I',
          'file_md5': 'md5_three_body',
          'last_read_position': 'cfi_local_01',
          'reading_percentage': 0.20,
          'update_time': t0.toIso8601String(),
        },
        {
          'id': 2,
          'title': 'Principles',
          'file_md5': 'md5_principles',
          'last_read_position': 'cfi_principles_01',
          'reading_percentage': 0.10,
          'update_time': t0.toIso8601String(),
        },
      ];

      final remoteBooks = [
        {
          'title': 'Three Body I (Updated)',
          'file_md5': 'md5_three_body',
          'last_read_position': 'cfi_remote_02',
          'reading_percentage': 0.50,
          'update_time': t1.toIso8601String(), // Remote is newer
        },
        {
          'title': 'Clean Code',
          'file_md5': 'md5_clean_code',
          'last_read_position': 'cfi_clean_01',
          'reading_percentage': 0.0,
          'update_time': t1.toIso8601String(), // Remote new book
        },
      ];

      final merged = RecordMerger.mergeBooks(
        localBooks: localBooks,
        remoteBooks: remoteBooks,
      );

      expect(merged.length, 3); // Three Body, Principles, Clean Code

      final threeBody = merged.firstWhere((b) => b['file_md5'] == 'md5_three_body');
      expect(threeBody['last_read_position'], 'cfi_remote_02');
      expect(threeBody['reading_percentage'], 0.50);

      final cleanCode = merged.firstWhere((b) => b['file_md5'] == 'md5_clean_code');
      expect(cleanCode['title'], 'Clean Code');

      final principles = merged.firstWhere((b) => b['file_md5'] == 'md5_principles');
      expect(principles['reading_percentage'], 0.10);
    });

    test('mergeNotes handles cross-device ID translation, union, and tombstone soft deletion', () {
      final t0 = DateTime.utc(2026, 9, 1, 10, 0, 0);
      final t1 = DateTime.utc(2026, 9, 2, 10, 0, 0);

      // Local book mapping: md5_three_body -> local book_id = 99
      final md5ToLocalIdMap = {'md5_three_body': 99};

      final localNotes = [
        {
          'book_id': 99,
          'file_md5': 'md5_three_body',
          'cfi': 'cfi_note_1',
          'content': 'Note 1 created on local',
          'is_deleted': 0,
          'update_time': t0.toIso8601String(),
        },
        {
          'book_id': 99,
          'file_md5': 'md5_three_body',
          'cfi': 'cfi_note_2',
          'content': 'Note 2 deleted on local',
          'is_deleted': 1, // Deleted on local at t1
          'update_time': t1.toIso8601String(),
        },
      ];

      final remoteNotes = [
        {
          'file_md5': 'md5_three_body',
          'cfi': 'cfi_note_2',
          'content': 'Note 2 still alive on remote',
          'is_deleted': 0, // Remote had older copy at t0
          'update_time': t0.toIso8601String(),
        },
        {
          'file_md5': 'md5_three_body',
          'cfi': 'cfi_note_3',
          'content': 'Note 3 created on remote',
          'is_deleted': 0,
          'update_time': t0.toIso8601String(),
        },
      ];

      final merged = RecordMerger.mergeNotes(
        localNotes: localNotes,
        remoteNotes: remoteNotes,
        md5ToLocalBookId: md5ToLocalIdMap,
      );

      expect(merged.length, 3);

      final note1 = merged.firstWhere((n) => n['cfi'] == 'cfi_note_1');
      expect(note1['book_id'], 99);
      expect(note1['is_deleted'], 0);

      // Note 2: local had tombstone at t1 > remote at t0 -> Must be is_deleted = 1
      final note2 = merged.firstWhere((n) => n['cfi'] == 'cfi_note_2');
      expect(note2['is_deleted'], 1);

      // Note 3: remote note mapped to local book_id = 99
      final note3 = merged.firstWhere((n) => n['cfi'] == 'cfi_note_3');
      expect(note3['book_id'], 99);
      expect(note3['content'], 'Note 3 created on remote');
    });

    test('mergeReadingTimes takes max reading time per book md5 and date', () {
      final md5ToLocalIdMap = {'md5_book_A': 10};

      final localReadingTimes = [
        {
          'book_id': 10,
          'file_md5': 'md5_book_A',
          'date': '2026-09-02',
          'reading_time': 1200, // 20 mins
        },
      ];

      final remoteReadingTimes = [
        {
          'file_md5': 'md5_book_A',
          'date': '2026-09-02',
          'reading_time': 2400, // 40 mins
        },
        {
          'file_md5': 'md5_book_A',
          'date': '2026-09-01',
          'reading_time': 1800,
        },
      ];

      final merged = RecordMerger.mergeReadingTimes(
        localReadingTimes: localReadingTimes,
        remoteReadingTimes: remoteReadingTimes,
        md5ToLocalBookId: md5ToLocalIdMap,
      );

      expect(merged.length, 2);
      final today = merged.firstWhere((r) => r['date'] == '2026-09-02');
      expect(today['reading_time'], 2400); // Takes max 2400
      expect(today['book_id'], 10);
    });

    test('mergeNotes strips remote primary key id on new records and preserves local id on updates', () {
      final t0 = DateTime.utc(2026, 9, 1, 10, 0, 0);
      final t1 = DateTime.utc(2026, 9, 2, 10, 0, 0);

      final localNotes = [
        {
          'id': 101, // Local primary key
          'book_id': 5,
          'file_md5': 'md5_book',
          'cfi': 'cfi_existing',
          'content': 'Old local content',
          'update_time': t0.toIso8601String(),
        },
      ];

      final remoteNotes = [
        {
          'id': 999, // Remote primary key on other device
          'book_id': 888, // Remote book_id on other device
          'file_md5': 'md5_book',
          'cfi': 'cfi_existing',
          'content': 'New remote content',
          'update_time': t1.toIso8601String(), // Newer
        },
        {
          'id': 777, // Remote primary key for new note
          'book_id': 888,
          'file_md5': 'md5_book',
          'cfi': 'cfi_brand_new',
          'content': 'Brand new note on remote',
          'update_time': t1.toIso8601String(),
        },
      ];

      final merged = RecordMerger.mergeNotes(
        localNotes: localNotes,
        remoteNotes: remoteNotes,
        md5ToLocalBookId: {'md5_book': 5},
      );

      final updatedExisting = merged.firstWhere((n) => n['cfi'] == 'cfi_existing');
      expect(updatedExisting['id'], 101); // Local ID preserved! NOT remote 999
      expect(updatedExisting['book_id'], 5);
      expect(updatedExisting['content'], 'New remote content');

      final brandNew = merged.firstWhere((n) => n['cfi'] == 'cfi_brand_new');
      expect(brandNew['id'], isNull); // Remote ID 777 stripped! Ready for DAO INSERT
      expect(brandNew['book_id'], 5);
      expect(brandNew['content'], 'Brand new note on remote');
    });

    test('mergeNotes strictly sets book_id to 0 and never leaks remote foreign key when md5 is unmapped', () {
      final remoteNotes = [
        {
          'id': 123,
          'book_id': 9999, // Remote device book_id
          'file_md5': 'unmapped_remote_book_md5',
          'cfi': 'cfi_unmapped',
          'content': 'Note on unmapped book',
          'update_time': DateTime.utc(2026, 9, 2).toIso8601String(),
        },
      ];

      final merged = RecordMerger.mergeNotes(
        localNotes: [],
        remoteNotes: remoteNotes,
        md5ToLocalBookId: {}, // Empty mapping
      );

      expect(merged.length, 1);
      expect(merged.first['book_id'], 0); // Strictly 0, NOT remote 9999!
      expect(merged.first['id'], isNull);
    });
  });
}
