import 'dart:convert';

double clampReadingProgress(double value) {
  if (!value.isFinite) {
    return 0.0;
  }
  return value.clamp(0.0, 1.0).toDouble();
}

String encodeReadingRestoreTargetFromFraction(double fraction) {
  return jsonEncode({
    'fraction': clampReadingProgress(fraction),
  });
}

Object? decodeReadingRestoreTarget(
  String? rawValue, {
  double? fallbackFraction,
}) {
  final trimmed = rawValue?.trim() ?? '';
  if (trimmed.isNotEmpty) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final fraction = (decoded['fraction'] as num?)?.toDouble();
        if (fraction != null) {
          return {
            'fraction': clampReadingProgress(fraction),
          };
        }
        final cfi = decoded['cfi']?.toString();
        if (cfi != null && cfi.isNotEmpty) {
          return {
            'cfi': cfi,
            if (decoded['chapterIndex'] is num)
              'chapterIndex': (decoded['chapterIndex'] as num).toInt(),
          };
        }
      }
    } catch (_) {
      return trimmed;
    }
    return trimmed;
  }

  if (fallbackFraction == null) {
    return null;
  }

  final clampedFallback = clampReadingProgress(fallbackFraction);
  if (clampedFallback <= 0) {
    return null;
  }

  return {
    'fraction': clampedFallback,
  };
}
