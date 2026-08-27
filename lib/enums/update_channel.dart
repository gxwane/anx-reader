enum UpdateChannel {
  stable('stable'),
  preview('preview');

  final String code;
  const UpdateChannel(this.code);

  static UpdateChannel fromCode(String? code) {
    return UpdateChannel.values.firstWhere(
      (e) => e.code == code,
      orElse: () => UpdateChannel.preview,
    );
  }
}
