import 'dart:convert';

enum FontSource {
  book,
  systemUi,
  bundled,
  localCustom,
  downloaded,
  systemFont,
}

class FontModel {
  final String id;
  final String label;
  final String name;
  final String path;
  final FontSource source;
  final String? postscriptName;
  final int? fileSize;
  final bool isDeletable;

  FontModel({
    String? id,
    required this.label,
    required this.name,
    required this.path,
    this.source = FontSource.localCustom,
    this.postscriptName,
    this.fileSize,
    this.isDeletable = true,
  }) : id = id ??
            (postscriptName != null && postscriptName.isNotEmpty
                ? 'postscript:$postscriptName'
                : 'file:${path.split('/').last.split('\\').last}');

  factory FontModel.book({String? label}) => FontModel(
        id: 'preset:book',
        label: label ?? 'Follow Book',
        name: 'book',
        path: 'book',
        source: FontSource.book,
        isDeletable: false,
      );

  factory FontModel.systemUi({String? label}) => FontModel(
        id: 'preset:system',
        label: label ?? 'System UI',
        name: 'system',
        path: 'system',
        source: FontSource.systemUi,
        isDeletable: false,
      );

  factory FontModel.bundled({
    required String label,
    required String name,
    required String path,
    String? postscriptName,
  }) =>
      FontModel(
        id: postscriptName != null && postscriptName.isNotEmpty
            ? 'postscript:$postscriptName'
            : 'bundled:$name',
        label: label,
        name: name,
        path: path,
        source: FontSource.bundled,
        postscriptName: postscriptName,
        isDeletable: false,
      );

  factory FontModel.systemFont({
    required String familyName,
    String? label,
  }) =>
      FontModel(
        id: 'system:$familyName',
        label: label ?? familyName,
        name: familyName,
        path: '',
        source: FontSource.systemFont,
        isDeletable: false,
      );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'name': name,
      'path': normalizedPath,
      'source': source.name,
      if (postscriptName != null) 'postscriptName': postscriptName,
      if (fileSize != null) 'fileSize': fileSize,
      'isDeletable': isDeletable,
    };
  }

  String toJson() => jsonEncode(toMap());

  String get normalizedPath => path.replaceAll('\\', '/');

  String get litePath => normalizedPath.split('/').last;

  /// Dynamically resolves the HTTP URL using the runtime server port.
  String getWebUrl(int serverPort) {
    if (source == FontSource.book ||
        source == FontSource.systemUi ||
        source == FontSource.systemFont) {
      return '';
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final file = normalizedPath;
    if (file.isEmpty) return '';
    return 'http://127.0.0.1:$serverPort/fonts/$file';
  }

  static FontModel fromJson(String fontJson) {
    final Map<String, dynamic> json = jsonDecode(fontJson);
    final rawPath = (json['path'] as String? ?? '').replaceAll('\\', '/');
    final lite = rawPath.split('/').last;
    final name = json['name'] as String? ?? 'customFont';
    final label = json['label'] as String? ?? lite;

    // Detect presets
    if (lite == 'book' || name == 'book') {
      return FontModel.book(label: label);
    }
    if (lite == 'system' || name == 'system') {
      return FontModel.systemUi(label: label);
    }

    // Source parsing
    final sourceStr = json['source'] as String?;
    FontSource source = FontSource.localCustom;
    if (sourceStr != null) {
      source = FontSource.values.firstWhere(
        (s) => s.name == sourceStr,
        orElse: () => FontSource.localCustom,
      );
    }

    final postscriptName = json['postscriptName'] as String?;
    final existingId = json['id'] as String?;
    final derivedId = existingId ??
        (postscriptName != null && postscriptName.isNotEmpty
            ? 'postscript:$postscriptName'
            : 'file:$lite');

    return FontModel(
      id: derivedId,
      label: label,
      name: name,
      path: rawPath.isNotEmpty ? rawPath : lite,
      source: source,
      postscriptName: postscriptName,
      fileSize: json['fileSize'] as int?,
      isDeletable: json['isDeletable'] as bool? ??
          (source == FontSource.localCustom ||
              source == FontSource.downloaded),
    );
  }

  FontModel copyWith({
    String? id,
    String? label,
    String? name,
    String? path,
    FontSource? source,
    String? postscriptName,
    int? fileSize,
    bool? isDeletable,
  }) {
    return FontModel(
      id: id ?? this.id,
      label: label ?? this.label,
      name: name ?? this.name,
      path: path ?? this.path,
      source: source ?? this.source,
      postscriptName: postscriptName ?? this.postscriptName,
      fileSize: fileSize ?? this.fileSize,
      isDeletable: isDeletable ?? this.isDeletable,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
