import 'package:flutter/services.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;
  final String? build;
  final String raw;

  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const [],
    this.build,
    required this.raw,
  });

  bool get isPreRelease => preRelease.isNotEmpty;

  /// Parse a version string, stripping prefixes like 'gx-v' or 'v'.
  factory AppVersion.parse(String input) {
    var clean = input.trim();
    if (clean.startsWith('gx-v')) {
      clean = clean.substring(4);
    } else if (clean.startsWith('v')) {
      clean = clean.substring(1);
    }

    String? buildMetadata;
    final plusIndex = clean.indexOf('+');
    if (plusIndex != -1) {
      buildMetadata = clean.substring(plusIndex + 1);
      clean = clean.substring(0, plusIndex);
    }

    List<String> preReleaseParts = [];
    final dashIndex = clean.indexOf('-');
    if (dashIndex != -1) {
      final preStr = clean.substring(dashIndex + 1);
      preReleaseParts = preStr.split('.').where((s) => s.isNotEmpty).toList();
      clean = clean.substring(0, dashIndex);
    }

    final coreParts = clean.split('.');
    final major = coreParts.isNotEmpty ? int.tryParse(coreParts[0]) ?? 0 : 0;
    final minor = coreParts.length > 1 ? int.tryParse(coreParts[1]) ?? 0 : 0;
    final patch = coreParts.length > 2 ? int.tryParse(coreParts[2]) ?? 0 : 0;

    return AppVersion(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: preReleaseParts,
      build: buildMetadata,
      raw: input,
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // SemVer 2.0: Normal version has higher precedence than pre-release version
    if (isPreRelease && !other.isPreRelease) return -1;
    if (!isPreRelease && other.isPreRelease) return 1;
    if (!isPreRelease && !other.isPreRelease) return 0;

    // Both are pre-releases, compare identifiers
    final minLen = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;

    for (int i = 0; i < minLen; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);

      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else if (aNum != null && bNum == null) {
        return -1; // Numeric identifiers have lower precedence than non-numeric
      } else if (aNum == null && bNum != null) {
        return 1;
      } else {
        final cmp = a.compareTo(b);
        if (cmp != 0) return cmp;
      }
    }

    return preRelease.length.compareTo(other.preRelease.length);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersion &&
          runtimeType == other.runtimeType &&
          compareTo(other) == 0;

  @override
  int get hashCode =>
      major.hashCode ^ minor.hashCode ^ patch.hashCode ^ preRelease.hashCode;

  @override
  String toString() {
    final core = '$major.$minor.$patch';
    final pre = isPreRelease ? '-${preRelease.join('.')}' : '';
    final b = build != null ? '+$build' : '';
    return '$core$pre$b';
  }
}

Future<String> getAppVersion() async {
  final pubspecContent = await rootBundle.loadString('pubspec.yaml');
  final pubspec = Pubspec.parse(pubspecContent);
  return pubspec.version.toString();
}

Future<AppVersion> getCurrentAppVersion() async {
  final rawVersion = await getAppVersion();
  return AppVersion.parse(rawVersion);
}

