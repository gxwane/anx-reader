import 'dart:io';

import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:anx_reader/utils/log/common.dart';

/// Finds existing local backups without downloading, replacing or pruning data.
class LocalDatabaseBackups {
  static Future<List<String>> list({Directory? directory}) async {
    try {
      final root = directory ?? await getAnxCacheDir();
      final backups = <String>[];
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (name.startsWith('backup_database_') && name.endsWith('.db')) {
          backups.add(entry.path);
        }
      }
      return backups..sort((left, right) => right.compareTo(left));
    } catch (error) {
      AnxLog.warning('Cannot list local database backups: $error');
      return [];
    }
  }
}
