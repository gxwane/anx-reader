import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';

class Book {
  int id;
  String title;
  String coverPath;
  String filePath;
  String lastReadPosition;
  double readingPercentage;
  String author;
  bool isDeleted;
  String? description;
  double rating;
  int groupId;
  String? md5;
  ReadingStatus status;
  DateTime? startReadingTime;
  DateTime? finishReadingTime;
  int readCount;
  DateTime createTime;
  DateTime updateTime;

  Book({
    required this.id,
    required this.title,
    required this.coverPath,
    required this.filePath,
    required this.lastReadPosition,
    required this.readingPercentage,
    required this.author,
    required this.isDeleted,
    this.description,
    required this.rating,
    this.groupId = 0,
    this.md5,
    this.status = ReadingStatus.unread,
    this.startReadingTime,
    this.finishReadingTime,
    this.readCount = 0,
    required this.createTime,
    required this.updateTime,
  });

  factory Book.mock() {
    return Book(
      id: 1,
      title: 'Mock Book',
      coverPath: '',
      filePath: '',
      lastReadPosition: '',
      readingPercentage: 0.78,
      author: 'Anx',
      isDeleted: false,
      rating: 0,
      status: ReadingStatus.unread,
      readCount: 0,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );
  }

  String get coverFullPath {
    return getBasePath(coverPath);
  }

  String get fileFullPath {
    return getBasePath(filePath);
  }

  Map<String, Object?> toMap() {
    return {
      'title': title,
      'cover_path': coverPath,
      'file_path': filePath,
      'last_read_position': lastReadPosition,
      'reading_percentage': readingPercentage,
      'author': author,
      'is_deleted': isDeleted ? 1 : 0,
      'description': description,
      'rating': rating,
      'group_id': groupId,
      'file_md5': md5,
      'reading_status': status.value,
      'start_reading_time': startReadingTime?.toIso8601String(),
      'finish_reading_time': finishReadingTime?.toIso8601String(),
      'read_count': readCount,
      'create_time': createTime.toIso8601String(),
      'update_time': updateTime.toIso8601String(),
    };
  }

  Book copyWith({
    int? id,
    String? title,
    String? coverPath,
    String? filePath,
    String? lastReadPosition,
    double? readingPercentage,
    String? author,
    bool? isDeleted,
    String? description,
    double? rating,
    int? groupId,
    String? md5,
    ReadingStatus? status,
    DateTime? startReadingTime,
    DateTime? finishReadingTime,
    int? readCount,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      coverPath: coverPath ?? this.coverPath,
      filePath: filePath ?? this.filePath,
      lastReadPosition: lastReadPosition ?? this.lastReadPosition,
      readingPercentage: readingPercentage ?? this.readingPercentage,
      author: author ?? this.author,
      isDeleted: isDeleted ?? this.isDeleted,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      groupId: groupId ?? this.groupId,
      md5: md5 ?? this.md5,
      status: status ?? this.status,
      startReadingTime: startReadingTime ?? this.startReadingTime,
      finishReadingTime: finishReadingTime ?? this.finishReadingTime,
      readCount: readCount ?? this.readCount,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
    );
  }

  factory Book.fromDb(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int,
      title: map['title'] as String? ?? '',
      coverPath: map['cover_path'] as String? ?? '',
      filePath: map['file_path'] as String? ?? '',
      lastReadPosition: map['last_read_position'] as String? ?? '',
      readingPercentage: (map['reading_percentage'] as num?)?.toDouble() ?? 0.0,
      author: map['author'] as String? ?? '',
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      description: map['description'] as String?,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      groupId: map['group_id'] as int? ?? 0,
      md5: map['file_md5'] as String?,
      status: ReadingStatus.fromValue(map['reading_status'] as int?),
      startReadingTime: map['start_reading_time'] != null
          ? DateTime.tryParse(map['start_reading_time'] as String)
          : null,
      finishReadingTime: map['finish_reading_time'] != null
          ? DateTime.tryParse(map['finish_reading_time'] as String)
          : null,
      readCount: (map['read_count'] as int?) ?? 0,
      createTime: DateTime.parse(map['create_time'] as String),
      updateTime: DateTime.parse(map['update_time'] as String),
    );
  }
}

