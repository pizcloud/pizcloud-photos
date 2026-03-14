import 'package:sqflite/sqflite.dart';

import 'media_db.dart';
import 'media_models.dart';

class MediaRepository {
  MediaRepository({MediaDatabase? database})
    : _database = database ?? MediaDatabase.instance;

  final MediaDatabase _database;

  Future<int> upsertLocalItems(
    List<MediaItem> items, {
    DateTime? updatedAt,
  }) async {
    if (items.isEmpty) {
      return 0;
    }
    final db = await _database.database;
    final batch = db.batch();
    final DateTime resolvedUpdatedAt = updatedAt ?? DateTime.now();
    int processed = 0;

    for (final item in items) {
      if (item.localId == null || item.localId!.isEmpty) {
        continue;
      }
      final map = _localInsertMap(item, resolvedUpdatedAt);

      batch.insert(
        'media_items',
        map,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      batch.rawUpdate(
        '''
UPDATE media_items SET
  checksum = ?,
  type = ?,
  file_name = ?,
  mime_type = ?,
  width = ?,
  height = ?,
  duration_ms = ?,
  size_bytes = ?,
  created_at = ?,
  modified_at = ?,
  sync_state = CASE WHEN remote_id IS NOT NULL THEN ? ELSE ? END,
  updated_at = ?
WHERE local_id = ?
''',
        [
          item.checksum,
          _typeToString(item.type),
          item.fileName,
          item.mimeType,
          item.width,
          item.height,
          item.durationMs,
          item.sizeBytes,
          item.createdAt?.millisecondsSinceEpoch,
          item.modifiedAt?.millisecondsSinceEpoch,
          SyncState.synced.index,
          SyncState.localOnly.index,
          resolvedUpdatedAt.millisecondsSinceEpoch,
          item.localId,
        ],
      );
      processed++;
    }

    await batch.commit(noResult: true);
    return processed;
  }

  Future<int> upsertRemoteItems(List<MediaItem> items) async {
    if (items.isEmpty) {
      return 0;
    }
    final db = await _database.database;
    final batch = db.batch();
    final updatedAt = DateTime.now();
    int processed = 0;

    for (final item in items) {
      if (item.remoteId == null || item.remoteId!.isEmpty) {
        continue;
      }
      final map = _remoteInsertMap(item, updatedAt);

      batch.insert(
        'media_items',
        map,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      batch.rawUpdate(
        '''
UPDATE media_items SET
  checksum = ?,
  type = ?,
  file_name = ?,
  mime_type = ?,
  width = ?,
  height = ?,
  duration_ms = ?,
  size_bytes = ?,
  created_at = ?,
  modified_at = ?,
  cloud_url = ?,
  sync_state = CASE WHEN local_id IS NOT NULL THEN ? ELSE ? END,
  updated_at = ?
WHERE remote_id = ?
''',
        [
          item.checksum,
          _typeToString(item.type),
          item.fileName,
          item.mimeType,
          item.width,
          item.height,
          item.durationMs,
          item.sizeBytes,
          item.createdAt?.millisecondsSinceEpoch,
          item.modifiedAt?.millisecondsSinceEpoch,
          item.cloudUrl,
          SyncState.synced.index,
          SyncState.cloudOnly.index,
          updatedAt.millisecondsSinceEpoch,
          item.remoteId,
        ],
      );
      processed++;
    }

    await batch.commit(noResult: true);
    return processed;
  }

  Future<void> markSynced({
    required String localId,
    required String remoteId,
  }) async {
    final db = await _database.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final localRows = await txn.query(
        'media_items',
        where: 'local_id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      final remoteRows = await txn.query(
        'media_items',
        where: 'remote_id = ?',
        whereArgs: [remoteId],
        limit: 1,
      );

      Map<String, Object?> merged = {};
      int? localRowId;
      if (localRows.isNotEmpty) {
        merged.addAll(localRows.first);
        localRowId = localRows.first['id'] as int?;
      }
      if (remoteRows.isNotEmpty) {
        for (final entry in remoteRows.first.entries) {
          merged.putIfAbsent(entry.key, () => entry.value);
        }
      }

      if (localRowId != null) {
        await txn.update(
          'media_items',
          {
            'remote_id': remoteId,
            'checksum': merged['checksum'],
            'cloud_url': merged['cloud_url'],
            'sync_state': SyncState.synced.index,
            'updated_at': nowMs,
          },
          where: 'id = ?',
          whereArgs: [localRowId],
        );
        if (remoteRows.isNotEmpty &&
            (remoteRows.first['id'] as int?) != localRowId) {
          await txn.delete(
            'media_items',
            where: 'remote_id = ?',
            whereArgs: [remoteId],
          );
        }
        return;
      }

      if (remoteRows.isNotEmpty) {
        await txn.update(
          'media_items',
          {
            'local_id': localId,
            'sync_state': SyncState.synced.index,
            'updated_at': nowMs,
          },
          where: 'remote_id = ?',
          whereArgs: [remoteId],
        );
        return;
      }

      // If neither local nor remote row exists, do nothing.
    });
  }

  Future<List<MediaItem>> fetchItems({
    SyncState? syncState,
    MediaType? type,
    int? limit,
    int? offset,
    bool newestFirst = true,
  }) async {
    final db = await _database.database;
    final whereParts = <String>[];
    final whereArgs = <Object?>[];

    if (syncState != null) {
      whereParts.add('sync_state = ?');
      whereArgs.add(syncState.index);
    }
    if (type != null) {
      whereParts.add('type = ?');
      whereArgs.add(_typeToString(type));
    }

    final rows = await db.query(
      'media_items',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: newestFirst ? 'created_at DESC' : 'created_at ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(MediaItem.fromDbMap).toList();
  }

  Future<List<MediaItem>> fetchLocalItems({
    MediaType? type,
    int? limit,
    int? offset,
    bool newestFirst = true,
  }) async {
    final db = await _database.database;
    final whereParts = <String>['local_id IS NOT NULL'];
    final whereArgs = <Object?>[];
    if (type != null) {
      whereParts.add('type = ?');
      whereArgs.add(_typeToString(type));
    }

    final rows = await db.query(
      'media_items',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: newestFirst
          ? 'COALESCE(created_at, modified_at) DESC'
          : 'COALESCE(created_at, modified_at) ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(MediaItem.fromDbMap).toList();
  }

  Future<DateTime?> latestLocalModifiedAt() async {
    final db = await _database.database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
SELECT MAX(COALESCE(modified_at, created_at)) AS ts
FROM media_items
WHERE local_id IS NOT NULL
''');
    if (rows.isEmpty) {
      return null;
    }
    final Object? value = rows.first['ts'];
    final int? milliseconds = value is int ? value : int.tryParse('$value');
    if (milliseconds == null || milliseconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  Future<int> reconcileMissingLocalItems({required DateTime scanMarker}) async {
    final db = await _database.database;
    final int markerMs = scanMarker.millisecondsSinceEpoch;
    return db.transaction<int>((txn) async {
      final int movedToCloudOnly = await txn.rawUpdate(
        '''
UPDATE media_items
SET local_id = NULL,
    sync_state = ?,
    updated_at = ?
WHERE local_id IS NOT NULL
  AND updated_at < ?
  AND remote_id IS NOT NULL
''',
        [SyncState.cloudOnly.index, markerMs, markerMs],
      );

      final int deletedLocalOnly = await txn.rawDelete(
        '''
DELETE FROM media_items
WHERE local_id IS NOT NULL
  AND updated_at < ?
  AND remote_id IS NULL
''',
        [markerMs],
      );

      return movedToCloudOnly + deletedLocalOnly;
    });
  }

  Future<int?> getMetaInt(String key) async {
    final db = await _database.database;
    final rows = await db.query(
      'media_meta',
      columns: <String>['int_value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final Object? value = rows.first['int_value'];
    if (value is int) {
      return value;
    }
    return int.tryParse('$value');
  }

  Future<void> setMetaInt(String key, int value) async {
    final db = await _database.database;
    await db.insert('media_meta', <String, Object?>{
      'key': key,
      'int_value': value,
      'text_value': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> countBySyncState(SyncState state) async {
    final db = await _database.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM media_items WHERE sync_state = ?',
        [state.index],
      ),
    );
    return result ?? 0;
  }

  Future<int> countLocalItems({MediaType? type}) async {
    final db = await _database.database;
    final StringBuffer sql = StringBuffer(
      'SELECT COUNT(*) FROM media_items WHERE local_id IS NOT NULL',
    );
    final List<Object?> args = <Object?>[];
    if (type != null) {
      sql.write(' AND type = ?');
      args.add(_typeToString(type));
    }
    final int? result = Sqflite.firstIntValue(
      await db.rawQuery(sql.toString(), args),
    );
    return result ?? 0;
  }

  Map<String, Object?> _localInsertMap(MediaItem item, DateTime updatedAt) {
    return {
      'local_id': item.localId,
      'checksum': item.checksum,
      'type': _typeToString(item.type),
      'file_name': item.fileName,
      'mime_type': item.mimeType,
      'width': item.width,
      'height': item.height,
      'duration_ms': item.durationMs,
      'size_bytes': item.sizeBytes,
      'created_at': item.createdAt?.millisecondsSinceEpoch,
      'modified_at': item.modifiedAt?.millisecondsSinceEpoch,
      'sync_state': SyncState.localOnly.index,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  Map<String, Object?> _remoteInsertMap(MediaItem item, DateTime updatedAt) {
    return {
      'remote_id': item.remoteId,
      'checksum': item.checksum,
      'type': _typeToString(item.type),
      'file_name': item.fileName,
      'mime_type': item.mimeType,
      'width': item.width,
      'height': item.height,
      'duration_ms': item.durationMs,
      'size_bytes': item.sizeBytes,
      'created_at': item.createdAt?.millisecondsSinceEpoch,
      'modified_at': item.modifiedAt?.millisecondsSinceEpoch,
      'cloud_url': item.cloudUrl,
      'sync_state': SyncState.cloudOnly.index,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  String _typeToString(MediaType type) {
    switch (type) {
      case MediaType.photo:
        return 'photo';
      case MediaType.video:
        return 'video';
    }
  }
}
