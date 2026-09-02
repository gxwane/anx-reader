/// Single-book notes payload for WebDAV micro-sync and delta union merge.
class BookNotesPayload {
  final String fileMd5;
  final List<Map<String, dynamic>> notes;
  final DateTime updatedAt;

  BookNotesPayload({
    required this.fileMd5,
    required this.notes,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'file_md5': fileMd5,
        'notes': notes,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory BookNotesPayload.fromJson(Map<String, dynamic> json) =>
      BookNotesPayload(
        fileMd5: json['file_md5'] as String? ?? '',
        notes: List<Map<String, dynamic>>.from(
          (json['notes'] as List? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String).toUtc()
            : DateTime.now().toUtc(),
      );
}
