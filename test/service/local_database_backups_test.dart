import 'dart:io';

import 'package:anx_reader/service/local_database_backups.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lists existing backup files newest-name first without changing them',
      () async {
    final directory = await Directory.systemTemp.createTemp('anx_backup_list_');
    addTearDown(() => directory.delete(recursive: true));
    for (final name in [
      'backup_database_2026-01.db',
      'backup_database_2026-02.db',
      'unrelated.db',
    ]) {
      await File('${directory.path}/$name').writeAsString(name);
    }
    await Directory('${directory.path}/backup_database_directory.db').create();

    final paths = await LocalDatabaseBackups.list(directory: directory);

    expect(
      paths.map((path) => File(path).uri.pathSegments.last),
      ['backup_database_2026-02.db', 'backup_database_2026-01.db'],
    );
    expect(await directory.list().length, 4);
  });
}
