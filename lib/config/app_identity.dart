abstract final class AppIdentity {
  static const String displayName = 'Anx Reader GX Preview';
  static const String repositoryUrl = 'https://github.com/gxwane/anx-reader';
  static const String releasesUrl = '$repositoryUrl/releases';
  static const String releasesApiUrl =
      'https://api.github.com/repos/gxwane/anx-reader/releases/latest';
  static const String releasesListApiUrl =
      'https://api.github.com/repos/gxwane/anx-reader/releases';
  static const String documentationUrl = '$repositoryUrl/tree/develop/docs';
  static const String troubleshootingUrl =
      '$repositoryUrl/blob/develop/docs/troubleshooting.md';
  static const String upstreamRepositoryUrl =
      'https://github.com/Anxcye/anx-reader';
  static const String upstreamDocumentationUrl = 'https://anx.anxcye.com/docs';
  static const String previewSyncRoot = 'anx-reader-gx-preview';

  static String syncPath([String relativePath = '']) {
    final String normalized =
        relativePath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    return normalized.isEmpty
        ? previewSyncRoot
        : '$previewSyncRoot/$normalized';
  }
}
