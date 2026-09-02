/// Single-book progress payload for high-frequency lightweight WebDAV micro-sync.
class BookProgressPayload {
  final String fileMd5;
  final String lastReadPosition;
  final double readingPercentage;
  final String readingStatus;
  final DateTime updatedAt;
  final String deviceName;

  BookProgressPayload({
    required this.fileMd5,
    required this.lastReadPosition,
    required this.readingPercentage,
    required this.readingStatus,
    required this.updatedAt,
    required this.deviceName,
  });

  Map<String, dynamic> toJson() => {
        'file_md5': fileMd5,
        'last_read_position': lastReadPosition,
        'reading_percentage': readingPercentage,
        'reading_status': readingStatus,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'device_name': deviceName,
      };

  factory BookProgressPayload.fromJson(Map<String, dynamic> json) =>
      BookProgressPayload(
        fileMd5: json['file_md5'] as String? ?? '',
        lastReadPosition: json['last_read_position'] as String? ?? '',
        readingPercentage:
            (json['reading_percentage'] as num?)?.toDouble() ?? 0.0,
        readingStatus: json['reading_status'] as String? ?? 'reading',
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String).toUtc()
            : DateTime.now().toUtc(),
        deviceName: json['device_name'] as String? ?? 'Unknown Device',
      );
}
