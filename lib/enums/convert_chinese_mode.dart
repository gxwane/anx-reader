enum ConvertChineseMode {
  none,
  t2s,
  s2t,
  s2tw,
  s2hk,
}

ConvertChineseMode getConvertChineseMode(String? name) {
  if (name == null) return ConvertChineseMode.none;
  return ConvertChineseMode.values.firstWhere(
    (e) => e.name == name,
    orElse: () => ConvertChineseMode.none,
  );
}
