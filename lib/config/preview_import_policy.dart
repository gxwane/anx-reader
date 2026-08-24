abstract final class PreviewImportPolicy {
  static const Set<String> syncConfigurationKeys = <String>{
    'syncProtocol',
    'webdavInfo',
    'ftpInfo',
    's3Info',
    'googleDriveInfo',
    'oneDriveInfo',
    'dropboxInfo',
    'webdavStatus',
    'lastUploadBookDate',
  };

  static const Set<String> upstreamBackupSkipKeys = <String>{
    ...syncConfigurationKeys,
    'customStoragePath',
  };
}
