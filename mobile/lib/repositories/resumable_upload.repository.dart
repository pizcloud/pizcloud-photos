import 'dart:convert';

import 'package:cancellation_token_http/http.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/upload/resumable_upload.model.dart';

final resumableUploadRepositoryProvider = Provider((ref) => ResumableUploadRepository());

class ResumableUploadHttpException implements Exception {
  final int statusCode;
  final String message;
  final dynamic details;

  const ResumableUploadHttpException({required this.statusCode, required this.message, this.details});

  bool get isUnsupportedEndpoint => const {404, 405, 501}.contains(statusCode);

  @override
  String toString() => 'ResumableUploadHttpException($statusCode): $message';
}

class ResumableUploadPreparedSession {
  final String cacheKey;
  final String? sessionId;
  final String? duplicateAssetId;
  final bool? duplicateIsTrashed;
  final int chunkSize;
  final int totalChunks;
  final List<int> uploadedChunks;

  const ResumableUploadPreparedSession({
    required this.cacheKey,
    required this.sessionId,
    required this.duplicateAssetId,
    required this.duplicateIsTrashed,
    required this.chunkSize,
    required this.totalChunks,
    required this.uploadedChunks,
  });

  bool get isDuplicate => duplicateAssetId != null;
}

class ResumableUploadCompleteResponse {
  final int statusCode;
  final Map<String, dynamic> body;

  const ResumableUploadCompleteResponse({required this.statusCode, required this.body});
}

class ResumableUploadRepository {
  Future<ResumableUploadPreparedSession> prepareSession({
    required Client httpClient,
    required String endpoint,
    required Map<String, String> headers,
    required ResumableUploadSessionCreateRequest request,
    CancellationToken? cancellationToken,
  }) async {
    final cacheKey = request.cacheKey;
    final cachedSessionId = _getSessionIdFromCache(cacheKey);
    final statusUrl = Uri.parse('$endpoint/assets/upload-sessions');

    if (cachedSessionId != null && cachedSessionId.isNotEmpty) {
      try {
        final response = await _requestJson(
          httpClient: httpClient,
          method: 'GET',
          uri: Uri.parse('$statusUrl/$cachedSessionId'),
          headers: headers,
          cancellationToken: cancellationToken,
        );
        final session = ResumableUploadSessionStatusResponse.fromMap(response.body);
        if (session.id.isNotEmpty && session.chunkSize > 0 && session.totalChunks > 0) {
          await _setSessionCacheEntry(
            cacheKey: cacheKey,
            entry: ResumableUploadSessionCacheEntry(
              sessionId: session.id,
              deviceAssetId: request.deviceAssetId,
              fileSize: request.fileSize,
              fileModifiedAt: request.fileModifiedAt,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          return ResumableUploadPreparedSession(
            cacheKey: cacheKey,
            sessionId: session.id,
            duplicateAssetId: null,
            duplicateIsTrashed: null,
            chunkSize: session.chunkSize,
            totalChunks: session.totalChunks,
            uploadedChunks: session.uploadedChunks,
          );
        }

        await _removeSessionCacheEntry(cacheKey);
      } on ResumableUploadHttpException catch (error) {
        if (error.statusCode == 404) {
          await _removeSessionCacheEntry(cacheKey);
        } else {
          rethrow;
        }
      }
    }

    final createResponse = await _requestJson(
      httpClient: httpClient,
      method: 'POST',
      uri: statusUrl,
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(request.toMap()),
      cancellationToken: cancellationToken,
    );

    final session = ResumableUploadSessionCreateResponse.fromMap(createResponse.body);
    if (session.status == ResumableUploadSessionStatus.duplicate) {
      await _removeSessionCacheEntry(cacheKey);
      return ResumableUploadPreparedSession(
        cacheKey: cacheKey,
        sessionId: null,
        duplicateAssetId: session.assetId,
        duplicateIsTrashed: session.isTrashed,
        chunkSize: request.chunkSize,
        totalChunks: request.totalChunks,
        uploadedChunks: const <int>[],
      );
    }

    if (session.id == null ||
        session.id!.isEmpty ||
        session.chunkSize == null ||
        session.totalChunks == null ||
        session.uploadedChunks == null) {
      throw const FormatException('Invalid upload session create response');
    }

    await _setSessionCacheEntry(
      cacheKey: cacheKey,
      entry: ResumableUploadSessionCacheEntry(
        sessionId: session.id!,
        deviceAssetId: request.deviceAssetId,
        fileSize: request.fileSize,
        fileModifiedAt: request.fileModifiedAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    return ResumableUploadPreparedSession(
      cacheKey: cacheKey,
      sessionId: session.id!,
      duplicateAssetId: null,
      duplicateIsTrashed: null,
      chunkSize: session.chunkSize!,
      totalChunks: session.totalChunks!,
      uploadedChunks: session.uploadedChunks!,
    );
  }

  Future<ResumableUploadSessionChunkResponse> uploadChunk({
    required Client httpClient,
    required String endpoint,
    required Map<String, String> headers,
    required String sessionId,
    required int chunkIndex,
    required List<int> chunk,
    CancellationToken? cancellationToken,
  }) async {
    final response = await _requestJson(
      httpClient: httpClient,
      method: 'PUT',
      uri: Uri.parse('$endpoint/assets/upload-sessions/$sessionId/chunks/$chunkIndex'),
      headers: {...headers, 'Content-Type': 'application/octet-stream'},
      body: chunk,
      cancellationToken: cancellationToken,
    );
    return ResumableUploadSessionChunkResponse.fromMap(response.body);
  }

  Future<ResumableUploadCompleteResponse> completeSession({
    required Client httpClient,
    required String endpoint,
    required Map<String, String> headers,
    required String sessionId,
    required String cacheKey,
    CancellationToken? cancellationToken,
  }) async {
    final response = await _requestJson(
      httpClient: httpClient,
      method: 'POST',
      uri: Uri.parse('$endpoint/assets/upload-sessions/$sessionId/complete'),
      headers: headers,
      cancellationToken: cancellationToken,
    );
    await _removeSessionCacheEntry(cacheKey);
    return ResumableUploadCompleteResponse(statusCode: response.statusCode, body: response.body);
  }

  Future<void> deleteSession({
    required Client httpClient,
    required String endpoint,
    required Map<String, String> headers,
    required String sessionId,
    String? cacheKey,
    CancellationToken? cancellationToken,
  }) async {
    try {
      await _requestJson(
        httpClient: httpClient,
        method: 'DELETE',
        uri: Uri.parse('$endpoint/assets/upload-sessions/$sessionId'),
        headers: headers,
        cancellationToken: cancellationToken,
      );
    } on ResumableUploadHttpException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
    } finally {
      if (cacheKey != null && cacheKey.isNotEmpty) {
        await _removeSessionCacheEntry(cacheKey);
      }
    }
  }

  Future<void> removeCachedSession(String cacheKey) {
    return _removeSessionCacheEntry(cacheKey);
  }

  Future<_JsonResponse> _requestJson({
    required Client httpClient,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Object? body,
    CancellationToken? cancellationToken,
  }) async {
    final response = await _send(
      httpClient: httpClient,
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      cancellationToken: cancellationToken,
    );

    Map<String, dynamic> decoded = {};
    if (response.body.isNotEmpty) {
      try {
        final dynamic jsonBody = jsonDecode(response.body);
        if (jsonBody is Map<String, dynamic>) {
          decoded = jsonBody;
        } else if (jsonBody is Map) {
          decoded = jsonBody.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        decoded = {'message': response.body};
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final dynamic messageValue = decoded['message'] ?? decoded['error'];
      final message = messageValue is String && messageValue.isNotEmpty
          ? messageValue
          : (response.reasonPhrase ?? 'Request failed');
      throw ResumableUploadHttpException(statusCode: response.statusCode, message: message, details: decoded);
    }

    return _JsonResponse(statusCode: response.statusCode, body: decoded);
  }

  Future<Response> _send({
    required Client httpClient,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Object? body,
    CancellationToken? cancellationToken,
  }) {
    switch (method) {
      case 'GET':
        return httpClient.get(uri, headers: headers, cancellationToken: cancellationToken);
      case 'POST':
        return httpClient.post(uri, headers: headers, body: body, cancellationToken: cancellationToken);
      case 'PUT':
        return httpClient.put(uri, headers: headers, body: body, cancellationToken: cancellationToken);
      case 'DELETE':
        return httpClient.delete(uri, headers: headers, cancellationToken: cancellationToken);
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }
  }

  Map<String, ResumableUploadSessionCacheEntry> _readSessionCache() {
    final value = Store.tryGet(StoreKey.resumableUploadSessions);
    if (value == null || value.isEmpty) {
      return {};
    }

    try {
      final dynamic decoded = jsonDecode(value);
      if (decoded is! Map) {
        return {};
      }

      final cache = <String, ResumableUploadSessionCacheEntry>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final dynamic rawValue = entry.value;
        if (rawValue is Map<String, dynamic>) {
          cache[key] = ResumableUploadSessionCacheEntry.fromMap(rawValue);
          continue;
        }
        if (rawValue is Map) {
          cache[key] = ResumableUploadSessionCacheEntry.fromMap(
            rawValue.map((entryKey, entryValue) => MapEntry(entryKey.toString(), entryValue)),
          );
        }
      }

      return cache;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeSessionCache(Map<String, ResumableUploadSessionCacheEntry> cache) async {
    final serialized = cache.map((key, value) => MapEntry(key, value.toMap()));
    await Store.put(StoreKey.resumableUploadSessions, jsonEncode(serialized));
  }

  String? _getSessionIdFromCache(String cacheKey) {
    final entry = _readSessionCache()[cacheKey];
    if (entry == null || entry.sessionId.isEmpty) {
      return null;
    }
    return entry.sessionId;
  }

  Future<void> _setSessionCacheEntry({
    required String cacheKey,
    required ResumableUploadSessionCacheEntry entry,
  }) async {
    final cache = _readSessionCache();
    cache[cacheKey] = entry;
    await _writeSessionCache(cache);
  }

  Future<void> _removeSessionCacheEntry(String cacheKey) async {
    final cache = _readSessionCache();
    if (!cache.containsKey(cacheKey)) {
      return;
    }
    cache.remove(cacheKey);
    if (cache.isEmpty) {
      await Store.delete(StoreKey.resumableUploadSessions);
      return;
    }
    await _writeSessionCache(cache);
  }
}

class _JsonResponse {
  final int statusCode;
  final Map<String, dynamic> body;

  const _JsonResponse({required this.statusCode, required this.body});
}
