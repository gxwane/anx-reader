enum ReadingStatus {
  unread(0),
  reading(1),
  finished(2),
  abandoned(3);

  final int value;
  const ReadingStatus(this.value);

  static ReadingStatus fromValue(int? value) {
    if (value == null) return ReadingStatus.unread;
    return ReadingStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ReadingStatus.unread,
    );
  }
}
