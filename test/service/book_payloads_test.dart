import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/models/sync/book_progress_payload.dart';
import 'package:anx_reader/models/sync/book_notes_payload.dart';

void main() {
  group('BookProgressPayload Serialization Tests', () {
    test('serializes and deserializes accurately with immutable file_md5', () {
      final now = DateTime.utc(2026, 9, 2, 12, 0, 0);
      final payload = BookProgressPayload(
        fileMd5: 'md5_three_body_001',
        lastReadPosition: 'epubcfi(/6/4[chap01]!/4/2/10)',
        readingPercentage: 0.452,
        readingStatus: 'reading',
        updatedAt: now,
        deviceName: 'Pixel 9 Pro',
      );

      final json = payload.toJson();
      expect(json['file_md5'], 'md5_three_body_001');
      expect(json['last_read_position'], 'epubcfi(/6/4[chap01]!/4/2/10)');
      expect(json['reading_percentage'], 0.452);
      expect(json['reading_status'], 'reading');
      expect(json['device_name'], 'Pixel 9 Pro');

      final reconstructed = BookProgressPayload.fromJson(json);
      expect(reconstructed.fileMd5, payload.fileMd5);
      expect(reconstructed.lastReadPosition, payload.lastReadPosition);
      expect(reconstructed.readingPercentage, payload.readingPercentage);
      expect(reconstructed.readingStatus, payload.readingStatus);
      expect(reconstructed.updatedAt, payload.updatedAt);
      expect(reconstructed.deviceName, payload.deviceName);
    });
  });

  group('BookNotesPayload Serialization & Tombstone Tests', () {
    test('supports notes payload with soft deletion is_deleted flag', () {
      final now = DateTime.utc(2026, 9, 2, 12, 30, 0);
      final notes = [
        {
          'cfi': 'epubcfi(/6/2!/4/10)',
          'content': 'Important note',
          'type': 'highlight',
          'color': 'ff00ff00',
          'is_deleted': 0,
          'update_time': now.toIso8601String(),
        },
        {
          'cfi': 'epubcfi(/6/2!/4/20)',
          'content': 'Deleted note tombstone',
          'type': 'highlight',
          'color': 'ffff0000',
          'is_deleted': 1,
          'update_time': now.toIso8601String(),
        }
      ];

      final payload = BookNotesPayload(
        fileMd5: 'md5_principles_002',
        notes: notes,
        updatedAt: now,
      );

      final json = payload.toJson();
      expect(json['file_md5'], 'md5_principles_002');
      expect((json['notes'] as List).length, 2);

      final reconstructed = BookNotesPayload.fromJson(json);
      expect(reconstructed.fileMd5, 'md5_principles_002');
      expect(reconstructed.notes.length, 2);
      expect(reconstructed.notes[1]['is_deleted'], 1);
    });
  });
}
