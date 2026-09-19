import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/models/tb_group.dart';

/// Local group persistence. It knows only the v9 `parent_id` hierarchy.
class BookGroupDao {
  Future<TbGroup?> getGroup(int id) async {
    final db = await DBHelper().database;
    final rows = await db.query('tb_groups', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.single);
  }

  Future<void> validateHierarchy() async {
    final db = await DBHelper().database;
    final rows = await db.query('tb_groups');
    final parents = <int, int?>{};
    for (final row in rows) {
      final id = row['id'];
      final parent = row['parent_id'];
      if (id is! int || (parent != null && parent is! int)) {
        throw StateError('Invalid local group identity');
      }
      parents[id] = parent as int?;
    }
    if (!parents.containsKey(0) || parents[0] != null) {
      throw StateError('Root group is missing or invalid');
    }
    for (final id in parents.keys) {
      final visited = <int>{};
      int? current = id;
      while (current != null) {
        if (!visited.add(current)) {
          throw StateError('Local group hierarchy contains a cycle');
        }
        if (!parents.containsKey(current)) {
          throw StateError('Local group hierarchy has a missing parent');
        }
        current = parents[current];
      }
    }
  }

  Future<void> ensure(int id) async {
    if (id <= 0) throw ArgumentError.value(id, 'id', 'Invalid group ID');
    final db = await DBHelper().database;
    final existing = await getGroup(id);
    if (existing != null) {
      if (existing.isDeleted != 0) {
        throw StateError('Group $id is deleted');
      }
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.insert('tb_groups', {
      'id': id,
      'name': '...',
      'parent_id': 0,
      'is_deleted': 0,
      'create_time': now,
      'update_time': now,
    });
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await DBHelper().database;
    final changed = await db.update(
      'tb_groups',
      {
        'name': trimmed,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
    );
    if (changed != 1) throw StateError('Group $id not found');
  }

  Future<void> softDeleteIfEmpty(int id) async {
    if (id <= 0) return;
    final db = await DBHelper().database;
    final child = await db.rawQuery(
      'SELECT 1 FROM tb_groups WHERE parent_id = ? AND is_deleted = 0 LIMIT 1',
      [id],
    );
    final book = await db.rawQuery(
      'SELECT 1 FROM tb_books WHERE group_id = ? AND is_deleted = 0 LIMIT 1',
      [id],
    );
    if (child.isNotEmpty || book.isNotEmpty) {
      throw StateError('Cannot delete non-empty group $id');
    }
    await db.update(
      'tb_groups',
      {
        'is_deleted': 1,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  TbGroup _fromRow(Map<String, Object?> row) => TbGroup(
        id: row['id'] as int,
        name: row['name'] as String? ?? '',
        parentId: row['parent_id'] as int?,
        isDeleted: row['is_deleted'] as int? ?? 0,
        createTime: row['create_time'] as String?,
        updateTime: row['update_time'] as String?,
      );
}

final bookGroupDao = BookGroupDao();
