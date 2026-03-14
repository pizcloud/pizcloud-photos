import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class MediaDatabase {
  MediaDatabase._();

  static final MediaDatabase instance = MediaDatabase._();

  Database? _database;
  Completer<Database>? _opening;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final opening = _opening;
    if (opening != null) {
      return opening.future;
    }

    final completer = Completer<Database>();
    _opening = completer;
    try {
      final db = await _open();
      _database = db;
      completer.complete(db);
      return db;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _open() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, 'pizcloud_media.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE media_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  local_id TEXT UNIQUE,
  remote_id TEXT UNIQUE,
  checksum TEXT,
  type TEXT NOT NULL,
  file_name TEXT,
  mime_type TEXT,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  size_bytes INTEGER,
  created_at INTEGER,
  modified_at INTEGER,
  cloud_url TEXT,
  sync_state INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');

    await db.execute('CREATE INDEX idx_media_type ON media_items(type);');
    await db.execute(
      'CREATE INDEX idx_media_sync_state ON media_items(sync_state);',
    );
    await db.execute(
      'CREATE INDEX idx_media_created_at ON media_items(created_at);',
    );
    await db.execute(
      'CREATE INDEX idx_media_local_created_at ON media_items(local_id, created_at DESC);',
    );
    await db.execute(
      'CREATE INDEX idx_media_local_modified_at ON media_items(local_id, modified_at DESC);',
    );
    await db.execute('''
CREATE TABLE media_meta (
  key TEXT PRIMARY KEY,
  int_value INTEGER,
  text_value TEXT
);
''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_media_local_created_at ON media_items(local_id, created_at DESC);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_media_local_modified_at ON media_items(local_id, modified_at DESC);',
      );
      await db.execute('''
CREATE TABLE IF NOT EXISTS media_meta (
  key TEXT PRIMARY KEY,
  int_value INTEGER,
  text_value TEXT
);
''');
    }
  }

  Future<void> close() async {
    final db = _database ?? await _opening?.future;
    if (db == null) return;
    await db.close();
    _database = null;
  }
}
