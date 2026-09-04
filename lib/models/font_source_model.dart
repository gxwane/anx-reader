import 'dart:convert';

class FontSourceModel {
  final String id;
  final String name;
  final String manifestUrl;
  final bool isOfficial;

  const FontSourceModel({
    required this.id,
    required this.name,
    required this.manifestUrl,
    this.isOfficial = false,
  });

  static const official = FontSourceModel(
    id: 'official',
    name: 'Official Store',
    manifestUrl: 'https://fonts.anxcye.com/fonts-manifest.json',
    isOfficial: true,
  );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'manifestUrl': manifestUrl,
      'isOfficial': isOfficial,
    };
  }

  factory FontSourceModel.fromMap(Map<String, dynamic> map) {
    return FontSourceModel(
      id: map['id'] as String,
      name: map['name'] as String,
      manifestUrl: map['manifestUrl'] as String,
      isOfficial: (map['isOfficial'] as bool?) ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory FontSourceModel.fromJson(String source) =>
      FontSourceModel.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FontSourceModel &&
        other.id == id &&
        other.name == name &&
        other.manifestUrl == manifestUrl &&
        other.isOfficial == isOfficial;
  }

  @override
  int get hashCode => Object.hash(id, name, manifestUrl, isOfficial);
}
