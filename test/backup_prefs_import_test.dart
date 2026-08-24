import 'package:anx_reader/config/preview_import_policy.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> backupEntry(String type, Object? value) =>
    <String, Object?>{'type': type, 'value': value};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upstream backup import skips paths and sync credentials', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'customStoragePath': r'D:\GXPreview',
    });
    await Prefs().initPrefs();

    await Prefs().applyPrefsBackupMap(
      <String, dynamic>{
        prefsBackupVersionKey: prefsBackupSchemaVersion,
        'customStoragePath': backupEntry('string', r'D:\OfficialAnx'),
        'syncProtocol': backupEntry('string', 'webdav'),
        'webdavInfo': backupEntry(
          'string',
          '{"url":"https://official.example","username":"u","password":"p"}',
        ),
        'webdavStatus': backupEntry('bool', true),
        'lastUploadBookDate': backupEntry(
          'string',
          '2026-08-09T00:00:00.000',
        ),
        'reduceVibrationFeedback': backupEntry('bool', true),
      },
      additionalSkipKeys: PreviewImportPolicy.upstreamBackupSkipKeys,
    );

    expect(Prefs().customStoragePath, r'D:\GXPreview');
    expect(Prefs().syncProtocol, isNull);
    expect(Prefs().getSyncInfo(SyncProtocol.webdav), isEmpty);
    expect(Prefs().webdavStatus, isFalse);
    expect(Prefs().lastUploadBookDate, isNull);
    expect(Prefs().reduceVibrationFeedback, isTrue);
  });

  test('clearing sync configuration removes live imported state', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'syncProtocol': 'webdav',
      'webdavInfo':
          '{"url":"https://official.example","username":"u","password":"p"}',
      'webdavStatus': true,
      'lastUploadBookDate': '2026-08-09T00:00:00.000',
    });
    await Prefs().initPrefs();

    await Prefs().clearSyncConfiguration();

    expect(Prefs().syncProtocol, isNull);
    expect(Prefs().getSyncInfo(SyncProtocol.webdav), isEmpty);
    expect(Prefs().webdavStatus, isFalse);
    expect(Prefs().lastUploadBookDate, isNull);
  });
}
