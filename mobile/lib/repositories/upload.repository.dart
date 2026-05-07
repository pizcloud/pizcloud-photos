import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:cancellation_token_http/http.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/upload/resumable_upload.model.dart';
import 'package:immich_mobile/repositories/resumable_upload.repository.dart';
import 'package:logging/logging.dart';
import 'package:immich_mobile/utils/debug_print.dart';

class UploadTaskWithFile {
  final File file;
  final UploadTask task;
  // pizcloud
  final String deviceAssetId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String originalFileName;
  final bool isFavorite;
  final bool isLivePhoto;
  final String? checksum;
  final int? fileSize;

  const UploadTaskWithFile({
    required this.file,
    required this.task,
    required this.deviceAssetId,
    required this.createdAt,
    required this.modifiedAt,
    required this.originalFileName,
    required this.isFavorite,
    required this.isLivePhoto,
    this.checksum,
    this.fileSize,
  });

  int get resolvedFileSize => fileSize ?? file.lengthSync();
  // #pizcloud
}

final uploadRepositoryProvider = Provider((ref) => UploadRepository(ref.watch(resumableUploadRepositoryProvider)));

class UploadRepository {
  void Function(TaskStatusUpdate)? onUploadStatus;
  void Function(TaskProgressUpdate)? onTaskProgress;
  final ResumableUploadRepository _resumableUploadRepository; // pizcloud

  UploadRepository(this._resumableUploadRepository) {
    // pizcloud
    // pizcloud

    // FileDownloader().registerCallbacks(
    //   group: kBackupGroup,
    //   taskStatusCallback: (update) => onUploadStatus?.call(update),
    //   taskProgressCallback: (update) => onTaskProgress?.call(update),
    // );
    // FileDownloader().registerCallbacks(
    //   group: kBackupLivePhotoGroup,
    //   taskStatusCallback: (update) => onUploadStatus?.call(update),
    //   taskProgressCallback: (update) => onTaskProgress?.call(update),
    // );
    // FileDownloader().registerCallbacks(
    //   group: kManualUploadGroup,
    //   taskStatusCallback: (update) => onUploadStatus?.call(update),
    //   taskProgressCallback: (update) => onTaskProgress?.call(update),
    // );

    // Handle 409 Conflict to mark upload as failed
    FileDownloader().registerCallbacks(
      group: kBackupGroup,
      taskStatusCallback: (update) {
        final code = update.responseStatusCode;
        if (code == 409) {
          // Do not retry, mark failed
          try {
            onUploadStatus?.call(update.copyWith(status: TaskStatus.failed));
          } catch (_) {
            onUploadStatus?.call(update);
          }
          return;
        }
        onUploadStatus?.call(update);
      },
      taskProgressCallback: (update) => onTaskProgress?.call(update),
    );
    FileDownloader().registerCallbacks(
      group: kBackupLivePhotoGroup,
      taskStatusCallback: (update) {
        final code = update.responseStatusCode;
        if (code == 409) {
          try {
            onUploadStatus?.call(update.copyWith(status: TaskStatus.failed));
          } catch (_) {
            onUploadStatus?.call(update);
          }
          return;
        }
        onUploadStatus?.call(update);
      },
      taskProgressCallback: (update) => onTaskProgress?.call(update),
    );
    FileDownloader().registerCallbacks(
      group: kManualUploadGroup,
      taskStatusCallback: (update) {
        final code = update.responseStatusCode;
        if (code == 409) {
          try {
            onUploadStatus?.call(update.copyWith(status: TaskStatus.failed));
          } catch (_) {
            onUploadStatus?.call(update);
          }
          return;
        }
        onUploadStatus?.call(update);
      },
      taskProgressCallback: (update) => onTaskProgress?.call(update),
    );
    // #pizcloud
  }

  Future<void> enqueueBackground(UploadTask task) {
    return FileDownloader().enqueue(task);
  }

  Future<List<bool>> enqueueBackgroundAll(List<UploadTask> tasks) {
    return FileDownloader().enqueueAll(tasks);
  }

  Future<void> deleteDatabaseRecords(String group) {
    return FileDownloader().database.deleteAllRecords(group: group);
  }

  Future<bool> cancelAll(String group) {
    return FileDownloader().cancelAll(group: group);
  }

  Future<int> reset(String group) {
    return FileDownloader().reset(group: group);
  }

  /// Get a list of tasks that are ENQUEUED or RUNNING
  Future<List<Task>> getActiveTasks(String group) {
    return FileDownloader().allTasks(group: group);
  }

  Future<void> start() {
    return FileDownloader().start();
  }

  // pizcloud
  bool hasPendingResumableSessions() {
    return _resumableUploadRepository.hasPendingSessions();
  }

  Set<String> getPendingResumableSessionCacheKeys() {
    return _resumableUploadRepository.pendingSessionCacheKeys();
  }
  // #pizcloud

  Future<void> getUploadInfo() async {
    final [enqueuedTasks, runningTasks, canceledTasks, waitingTasks, pausedTasks] = await Future.wait([
      FileDownloader().database.allRecordsWithStatus(TaskStatus.enqueued, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.running, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.canceled, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.waitingToRetry, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.paused, group: kBackupGroup),
    ]);

    dPrint(
      () =>
          """
      Upload Info:
      Enqueued: ${enqueuedTasks.length}
      Running: ${runningTasks.length}
      Canceled: ${canceledTasks.length}
      Waiting: ${waitingTasks.length}
      Paused: ${pausedTasks.length}
    """,
    );
  }

  // pizcloud: Future<void> backupWithDartClient(...)
  // Return true if at least one asset was uploaded successfully in this batch.
  Future<bool> backupWithDartClient(Iterable<UploadTaskWithFile> tasks, CancellationToken cancelToken) async {
    final httpClient = Client();
    final String savedEndpoint = Store.get(StoreKey.serverEndpoint);

    Logger logger = Logger('UploadRepository');
    bool hasSuccessfulUpload = false;

    try {
      for (final candidate in tasks) {
        final fileSize = await candidate.file.length(); // pizcloud
        _emitStatus(TaskStatusUpdate(candidate.task, TaskStatus.running)); // pizcloud
        _emitProgress(TaskProgressUpdate(candidate.task, 0, fileSize)); // pizcloud

        if (cancelToken.isCancelled) {
          logger.warning("Backup was cancelled by the user");
          _emitCanceled(candidate.task, fileSize); // pizcloud
          break;
        }

        try {
          final result = await _uploadWithBestEffort(
            candidate: candidate,
            fileSize: fileSize,
            httpClient: httpClient,
            endpoint: savedEndpoint,
            cancelToken: cancelToken,
            logger: logger,
          );

          if (![200, 201].contains(result.statusCode)) {
            final errorCode = result.errorCode;
            final errorText = result.errorMessage;
            logger.warning(
              "Error(${errorCode ?? result.statusCode}) uploading ${candidate.task.filename} | Created on ${candidate.task.fields["fileCreatedAt"]} | $errorText",
            );

            _emitFailure(
              candidate.task,
              fileSize: fileSize,
              message: errorText ?? 'Upload failed',
              statusCode: result.statusCode,
              responseBody: result.rawBody,
            );

            if (result.statusCode == 409) {
              break;
            }
            continue;
          }

          hasSuccessfulUpload = true;
          _emitProgress(TaskProgressUpdate(candidate.task, 1, fileSize));
          _emitStatus(
            TaskStatusUpdate(candidate.task, TaskStatus.complete, null, result.rawBody, null, result.statusCode),
          );
        } on CancelledException {
          logger.warning("Backup was cancelled by the user");
          _emitCanceled(candidate.task, fileSize);
          break;
        } catch (error, stackTrace) {
          logger.warning("Error backup asset: ${error.toString()}: $stackTrace");
          final statusCode = error is ResumableUploadHttpException ? error.statusCode : null;
          final errorBody = error is ResumableUploadHttpException ? _safeJsonEncode(error.details) : null;
          _emitFailure(
            candidate.task,
            fileSize: fileSize,
            message: error.toString(),
            statusCode: statusCode,
            responseBody: errorBody,
          );
          continue;
        }
      }
    } finally {
      httpClient.close();
    }

    return hasSuccessfulUpload;
  }

  // pizcloud
  Future<_UploadExecutionResult> _uploadWithBestEffort({
    required UploadTaskWithFile candidate,
    required int fileSize,
    required Client httpClient,
    required String endpoint,
    required CancellationToken cancelToken,
    required Logger logger,
  }) async {
    if (_shouldUseResumableUpload(candidate, fileSize)) {
      try {
        return await _uploadResumableCandidate(
          candidate: candidate,
          fileSize: fileSize,
          httpClient: httpClient,
          endpoint: endpoint,
          cancelToken: cancelToken,
        );
      } on ResumableUploadHttpException catch (error) {
        if (!error.isUnsupportedEndpoint) {
          rethrow;
        }
        logger.warning(
          'Resumable upload endpoint unavailable (${error.statusCode}), fallback to multipart for ${candidate.task.filename}',
        );
      }
    }

    return _uploadMultipartCandidate(
      candidate: candidate,
      httpClient: httpClient,
      endpoint: endpoint,
      cancelToken: cancelToken,
    );
  }

  bool _shouldUseResumableUpload(UploadTaskWithFile candidate, int fileSize) {
    if (candidate.isLivePhoto) {
      return false;
    }
    return fileSize >= kResumableUploadMinFileSize;
  }

  Future<_UploadExecutionResult> _uploadMultipartCandidate({
    required UploadTaskWithFile candidate,
    required Client httpClient,
    required String endpoint,
    required CancellationToken cancelToken,
  }) async {
    // Legacy multipart upload path (kept for compatibility and fallback).
    final fileStream = candidate.file.openRead();
    final assetRawUploadData = MultipartFile(
      "assetData",
      fileStream,
      candidate.resolvedFileSize,
      filename: candidate.task.filename,
    );

    final baseRequest = MultipartRequest('POST', Uri.parse('$endpoint/assets'));

    baseRequest.headers.addAll(candidate.task.headers);
    baseRequest.fields.addAll(candidate.task.fields);
    baseRequest.files.add(assetRawUploadData);

    final response = await httpClient.send(baseRequest, cancellationToken: cancelToken);
    final responseBody = await _decodeResponseBody(await response.stream.bytesToString());

    return _UploadExecutionResult(statusCode: response.statusCode, body: responseBody);
  }

  Future<_UploadExecutionResult> _uploadResumableCandidate({
    required UploadTaskWithFile candidate,
    required int fileSize,
    required Client httpClient,
    required String endpoint,
    required CancellationToken cancelToken,
  }) async {
    final chunkSize = kResumableUploadChunkSize;
    final totalChunks = (fileSize / chunkSize).ceil();
    final createdAt = candidate.task.fields['fileCreatedAt'] ?? candidate.createdAt.toUtc().toIso8601String();
    final modifiedAt = candidate.task.fields['fileModifiedAt'] ?? candidate.modifiedAt.toUtc().toIso8601String();

    final sessionRequest = ResumableUploadSessionCreateRequest(
      deviceAssetId: candidate.deviceAssetId,
      deviceId: candidate.task.fields['deviceId'] ?? '',
      fileCreatedAt: createdAt,
      fileModifiedAt: modifiedAt,
      fileName: candidate.task.filename,
      filename: candidate.originalFileName,
      fileSize: fileSize,
      chunkSize: chunkSize,
      totalChunks: totalChunks,
      isFavorite: candidate.isFavorite,
      duration: candidate.task.fields['duration'] ?? '0',
      visibility: candidate.task.fields['visibility'],
      checksum: candidate.checksum,
    );

    final prepared = await _resumableUploadRepository.prepareSession(
      httpClient: httpClient,
      endpoint: endpoint,
      headers: candidate.task.headers,
      request: sessionRequest,
      cancellationToken: cancelToken,
    );

    if (prepared.isDuplicate) {
      if (prepared.duplicateAssetId == null || prepared.duplicateAssetId!.isEmpty) {
        throw const FormatException('Duplicate upload session response missing assetId');
      }
      return _UploadExecutionResult(
        statusCode: 200,
        body: {
          'id': prepared.duplicateAssetId,
          'status': 'duplicate',
          if (prepared.duplicateIsTrashed != null) 'isTrashed': prepared.duplicateIsTrashed,
        },
      );
    }

    if (prepared.sessionId == null || prepared.sessionId!.isEmpty) {
      throw const FormatException('Invalid upload session state');
    }

    final uploadedChunks = prepared.uploadedChunks.toSet();
    _emitResumableProgress(
      task: candidate.task,
      chunkSize: prepared.chunkSize,
      uploadedChunksCount: uploadedChunks.length,
      fileSize: fileSize,
    );

    for (int chunkIndex = 0; chunkIndex < prepared.totalChunks; chunkIndex++) {
      if (cancelToken.isCancelled) {
        throw const CancelledException();
      }
      if (uploadedChunks.contains(chunkIndex)) {
        continue;
      }

      final start = chunkIndex * prepared.chunkSize;
      final end = math.min(start + prepared.chunkSize, fileSize);
      final chunkData = await _readChunk(candidate.file, start, end);

      final response = await _resumableUploadRepository.uploadChunk(
        httpClient: httpClient,
        endpoint: endpoint,
        headers: candidate.task.headers,
        sessionId: prepared.sessionId!,
        chunkIndex: chunkIndex,
        chunk: chunkData,
        cancellationToken: cancelToken,
      );

      uploadedChunks
        ..clear()
        ..addAll(response.uploadedChunks);
      _emitResumableProgress(
        task: candidate.task,
        chunkSize: prepared.chunkSize,
        uploadedChunksCount: uploadedChunks.length,
        fileSize: fileSize,
      );
    }

    final complete = await _resumableUploadRepository.completeSession(
      httpClient: httpClient,
      endpoint: endpoint,
      headers: candidate.task.headers,
      sessionId: prepared.sessionId!,
      cacheKey: prepared.cacheKey,
      cancellationToken: cancelToken,
    );

    return _UploadExecutionResult(statusCode: complete.statusCode, body: complete.body);
  }

  Future<List<int>> _readChunk(File file, int start, int end) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(start, end)) {
      buffer.add(chunk);
    }
    return buffer.takeBytes();
  }

  Future<Map<String, dynamic>> _decodeResponseBody(String responseText) async {
    if (responseText.isEmpty) {
      return {};
    }
    try {
      final dynamic parsed = jsonDecode(responseText);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      if (parsed is Map) {
        return parsed.map((key, value) => MapEntry(key.toString(), value));
      }
      return {'message': responseText};
    } catch (_) {
      return {'message': responseText};
    }
  }

  void _emitStatus(TaskStatusUpdate update) {
    onUploadStatus?.call(update);
  }

  void _emitProgress(TaskProgressUpdate update) {
    onTaskProgress?.call(update);
  }

  void _emitCanceled(Task task, int fileSize) {
    _emitStatus(TaskStatusUpdate(task, TaskStatus.canceled));
    _emitProgress(TaskProgressUpdate(task, kUploadStatusCanceled, fileSize));
  }

  void _emitFailure(
    Task task, {
    required int fileSize,
    required String message,
    int? statusCode,
    String? responseBody,
  }) {
    final exception = statusCode != null ? TaskHttpException(message, statusCode) : TaskException(message);
    _emitStatus(TaskStatusUpdate(task, TaskStatus.failed, exception, responseBody, null, statusCode));
    _emitProgress(TaskProgressUpdate(task, kUploadStatusFailed, fileSize));
  }

  void _emitResumableProgress({
    required UploadTask task,
    required int chunkSize,
    required int uploadedChunksCount,
    required int fileSize,
  }) {
    final uploadedBytes = math.min(fileSize, uploadedChunksCount * chunkSize);
    final progress = fileSize <= 0 ? 0.0 : uploadedBytes / fileSize;
    _emitProgress(TaskProgressUpdate(task, progress.clamp(0.0, 1.0).toDouble(), fileSize));
  }

  String? _safeJsonEncode(dynamic payload) {
    if (payload == null) {
      return null;
    }
    try {
      return jsonEncode(payload);
    } catch (_) {
      return payload.toString();
    }
  }
}

class _UploadExecutionResult {
  final int statusCode;
  final Map<String, dynamic> body;

  const _UploadExecutionResult({required this.statusCode, required this.body});

  String? get errorMessage {
    final message = body['message'] ?? body['error'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
    return null;
  }

  int? get errorCode => (body['statusCode'] as num?)?.toInt();

  String? get rawBody {
    if (body.isEmpty) {
      return null;
    }
    try {
      return jsonEncode(body);
    } catch (_) {
      return body.toString();
    }
  }
}

// #pizcloud
