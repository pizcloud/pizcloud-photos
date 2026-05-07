import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/store.repository.dart';
import 'package:immich_mobile/repositories/resumable_upload.repository.dart';

void main() {
  late Drift db;
  final repository = ResumableUploadRepository();

  setUpAll(() async {
    db = Drift(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await StoreService.init(storeRepository: DriftStoreRepository(db));
  });

  tearDownAll(() async {
    try {
      await StoreService.I.dispose();
    } catch (_) {}
    await db.close();
  });

  tearDown(() async {
    await Store.delete(StoreKey.resumableUploadSessions);
  });

  test('pendingSessionCount returns zero when cache is empty', () {
    expect(repository.pendingSessionCount(), 0);
    expect(repository.hasPendingSessions(), isFalse);
  });

  test('pendingSessionCount counts only sessions with a non-empty session id', () async {
    final cachePayload = {
      'asset-a:100:2026-01-01T00:00:00Z': {
        'sessionId': 'session-a',
        'deviceAssetId': 'asset-a',
        'fileSize': 100,
        'fileModifiedAt': '2026-01-01T00:00:00Z',
        'updatedAt': 1710000000,
      },
      'asset-b:200:2026-01-01T00:00:00Z': {
        'sessionId': '',
        'deviceAssetId': 'asset-b',
        'fileSize': 200,
        'fileModifiedAt': '2026-01-01T00:00:00Z',
        'updatedAt': 1710000001,
      },
    };

    await Store.put(StoreKey.resumableUploadSessions, jsonEncode(cachePayload));

    expect(repository.pendingSessionCount(), 1);
    expect(repository.hasPendingSessions(), isTrue);
  });

  test('pendingSessionCount returns zero for malformed cache payload', () async {
    await Store.put(StoreKey.resumableUploadSessions, 'not-a-json-map');

    expect(repository.pendingSessionCount(), 0);
    expect(repository.hasPendingSessions(), isFalse);
  });
}
