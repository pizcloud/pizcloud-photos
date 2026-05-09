// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart'; // pizcloud
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/backup.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_asset.repository.dart'; // pizcloud
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/entities/store.entity.dart'; // pizcloud
import 'package:immich_mobile/services/upload.service.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:logging/logging.dart';

class EnqueueStatus {
  final int enqueueCount;
  final int totalCount;

  const EnqueueStatus({required this.enqueueCount, required this.totalCount});

  EnqueueStatus copyWith({int? enqueueCount, int? totalCount}) {
    return EnqueueStatus(enqueueCount: enqueueCount ?? this.enqueueCount, totalCount: totalCount ?? this.totalCount);
  }

  @override
  String toString() => 'EnqueueStatus(enqueueCount: $enqueueCount, totalCount: $totalCount)';
}

class DriftUploadStatus {
  final String taskId;
  final String filename;
  final double progress;
  final int fileSize;
  final String networkSpeedAsString;
  final bool? isFailed;
  final String? error;

  const DriftUploadStatus({
    required this.taskId,
    required this.filename,
    required this.progress,
    required this.fileSize,
    required this.networkSpeedAsString,
    this.isFailed,
    this.error,
  });

  DriftUploadStatus copyWith({
    String? taskId,
    String? filename,
    double? progress,
    int? fileSize,
    String? networkSpeedAsString,
    bool? isFailed,
    String? error,
  }) {
    return DriftUploadStatus(
      taskId: taskId ?? this.taskId,
      filename: filename ?? this.filename,
      progress: progress ?? this.progress,
      fileSize: fileSize ?? this.fileSize,
      networkSpeedAsString: networkSpeedAsString ?? this.networkSpeedAsString,
      isFailed: isFailed ?? this.isFailed,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'DriftUploadStatus(taskId: $taskId, filename: $filename, progress: $progress, fileSize: $fileSize, networkSpeedAsString: $networkSpeedAsString, isFailed: $isFailed, error: $error)';
  }

  @override
  bool operator ==(covariant DriftUploadStatus other) {
    if (identical(this, other)) return true;

    return other.taskId == taskId &&
        other.filename == filename &&
        other.progress == progress &&
        other.fileSize == fileSize &&
        other.networkSpeedAsString == networkSpeedAsString &&
        other.isFailed == isFailed &&
        other.error == error;
  }

  @override
  int get hashCode {
    return taskId.hashCode ^
        filename.hashCode ^
        progress.hashCode ^
        fileSize.hashCode ^
        networkSpeedAsString.hashCode ^
        isFailed.hashCode ^
        error.hashCode;
  }
}

// pizcloud
class DriftManualFailedUploadItem {
  final String taskId;
  final String filename;
  final String? error;
  final int? fileSize;
  final DateTime failedAt;

  const DriftManualFailedUploadItem({
    required this.taskId,
    required this.filename,
    required this.error,
    required this.fileSize,
    required this.failedAt,
  });

  DriftManualFailedUploadItem copyWith({
    String? taskId,
    String? filename,
    String? error,
    int? fileSize,
    DateTime? failedAt,
  }) {
    return DriftManualFailedUploadItem(
      taskId: taskId ?? this.taskId,
      filename: filename ?? this.filename,
      error: error ?? this.error,
      fileSize: fileSize ?? this.fileSize,
      failedAt: failedAt ?? this.failedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'taskId': taskId,
      'filename': filename,
      'error': error,
      'fileSize': fileSize,
      'failedAtMs': failedAt.millisecondsSinceEpoch,
    };
  }

  factory DriftManualFailedUploadItem.fromMap(Map<String, dynamic> map) {
    final dynamic failedAtRaw = map['failedAtMs'];
    final int? failedAtMs = failedAtRaw is int
        ? failedAtRaw
        : failedAtRaw is num
        ? failedAtRaw.toInt()
        : failedAtRaw is String
        ? int.tryParse(failedAtRaw)
        : null;
    final dynamic fileSizeRaw = map['fileSize'];
    final int? parsedFileSize = fileSizeRaw is int
        ? fileSizeRaw
        : fileSizeRaw is num
        ? fileSizeRaw.toInt()
        : fileSizeRaw is String
        ? int.tryParse(fileSizeRaw)
        : null;

    return DriftManualFailedUploadItem(
      taskId: (map['taskId'] as String?) ?? '',
      filename: (map['filename'] as String?) ?? '',
      error: map['error'] as String?,
      fileSize: parsedFileSize,
      failedAt: failedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(failedAtMs) : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'DriftManualFailedUploadItem(taskId: $taskId, filename: $filename, error: $error, fileSize: $fileSize, failedAt: $failedAt)';
  }

  @override
  bool operator ==(covariant DriftManualFailedUploadItem other) {
    if (identical(this, other)) return true;
    return other.taskId == taskId &&
        other.filename == filename &&
        other.error == error &&
        other.fileSize == fileSize &&
        other.failedAt == failedAt;
  }

  @override
  int get hashCode {
    return taskId.hashCode ^ filename.hashCode ^ error.hashCode ^ fileSize.hashCode ^ failedAt.hashCode;
  }
}

// pizcloud
const String kManualUploadInterruptedErrorCode = 'manual_upload_interrupted';

class DriftManualPendingUploadItem {
  final String taskId;
  final String filename;
  final int? fileSize;
  final DateTime queuedAt;

  const DriftManualPendingUploadItem({
    required this.taskId,
    required this.filename,
    required this.fileSize,
    required this.queuedAt,
  });

  DriftManualPendingUploadItem copyWith({String? taskId, String? filename, int? fileSize, DateTime? queuedAt}) {
    return DriftManualPendingUploadItem(
      taskId: taskId ?? this.taskId,
      filename: filename ?? this.filename,
      fileSize: fileSize ?? this.fileSize,
      queuedAt: queuedAt ?? this.queuedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'taskId': taskId,
      'filename': filename,
      'fileSize': fileSize,
      'queuedAtMs': queuedAt.millisecondsSinceEpoch,
    };
  }

  factory DriftManualPendingUploadItem.fromMap(Map<String, dynamic> map) {
    final dynamic queuedAtRaw = map['queuedAtMs'];
    final int? queuedAtMs = queuedAtRaw is int
        ? queuedAtRaw
        : queuedAtRaw is num
        ? queuedAtRaw.toInt()
        : queuedAtRaw is String
        ? int.tryParse(queuedAtRaw)
        : null;
    final dynamic fileSizeRaw = map['fileSize'];
    final int? parsedFileSize = fileSizeRaw is int
        ? fileSizeRaw
        : fileSizeRaw is num
        ? fileSizeRaw.toInt()
        : fileSizeRaw is String
        ? int.tryParse(fileSizeRaw)
        : null;

    return DriftManualPendingUploadItem(
      taskId: (map['taskId'] as String?) ?? '',
      filename: (map['filename'] as String?) ?? '',
      fileSize: parsedFileSize,
      queuedAt: queuedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(queuedAtMs) : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'DriftManualPendingUploadItem(taskId: $taskId, filename: $filename, fileSize: $fileSize, queuedAt: $queuedAt)';
  }

  @override
  bool operator ==(covariant DriftManualPendingUploadItem other) {
    if (identical(this, other)) return true;
    return other.taskId == taskId &&
        other.filename == filename &&
        other.fileSize == fileSize &&
        other.queuedAt == queuedAt;
  }

  @override
  int get hashCode => taskId.hashCode ^ filename.hashCode ^ fileSize.hashCode ^ queuedAt.hashCode;
}

enum ManualFailedUploadRetryResult { started, itemNotFound, alreadyInProgress, localAssetMissing, startFailed }
// #pizcloud

enum BackupError { none, syncFailed }

class DriftBackupState {
  final int totalCount;
  final int backupCount;
  final int remainderCount;
  final int processingCount;

  final int enqueueCount;
  final int enqueueTotalCount;

  final bool isSyncing;
  final bool isCanceling;
  final BackupError error;

  final Map<String, DriftUploadStatus> uploadItems;
  final Map<String, DriftManualFailedUploadItem> manualFailedUploadItems; // pizcloud
  final Map<String, DriftManualPendingUploadItem> manualPendingUploadItems; // pizcloud

  const DriftBackupState({
    required this.totalCount,
    required this.backupCount,
    required this.remainderCount,
    required this.processingCount,
    required this.enqueueCount,
    required this.enqueueTotalCount,
    required this.isCanceling,
    required this.isSyncing,
    required this.uploadItems,
    required this.manualFailedUploadItems, // pizcloud
    required this.manualPendingUploadItems, // pizcloud
    this.error = BackupError.none,
  });

  DriftBackupState copyWith({
    int? totalCount,
    int? backupCount,
    int? remainderCount,
    int? processingCount,
    int? enqueueCount,
    int? enqueueTotalCount,
    bool? isCanceling,
    bool? isSyncing,
    Map<String, DriftUploadStatus>? uploadItems,
    Map<String, DriftManualFailedUploadItem>? manualFailedUploadItems, // pizcloud
    Map<String, DriftManualPendingUploadItem>? manualPendingUploadItems, // pizcloud
    BackupError? error,
  }) {
    return DriftBackupState(
      totalCount: totalCount ?? this.totalCount,
      backupCount: backupCount ?? this.backupCount,
      remainderCount: remainderCount ?? this.remainderCount,
      processingCount: processingCount ?? this.processingCount,
      enqueueCount: enqueueCount ?? this.enqueueCount,
      enqueueTotalCount: enqueueTotalCount ?? this.enqueueTotalCount,
      isCanceling: isCanceling ?? this.isCanceling,
      isSyncing: isSyncing ?? this.isSyncing,
      uploadItems: uploadItems ?? this.uploadItems,
      manualFailedUploadItems: manualFailedUploadItems ?? this.manualFailedUploadItems, // pizcloud
      manualPendingUploadItems: manualPendingUploadItems ?? this.manualPendingUploadItems, // pizcloud
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'DriftBackupState(totalCount: $totalCount, backupCount: $backupCount, remainderCount: $remainderCount, processingCount: $processingCount, enqueueCount: $enqueueCount, enqueueTotalCount: $enqueueTotalCount, isCanceling: $isCanceling, isSyncing: $isSyncing, uploadItems: $uploadItems, manualFailedUploadItems: $manualFailedUploadItems, manualPendingUploadItems: $manualPendingUploadItems, error: $error)';
  }

  @override
  bool operator ==(covariant DriftBackupState other) {
    if (identical(this, other)) return true;
    final mapEquals = const DeepCollectionEquality().equals;

    return other.totalCount == totalCount &&
        other.backupCount == backupCount &&
        other.remainderCount == remainderCount &&
        other.processingCount == processingCount &&
        other.enqueueCount == enqueueCount &&
        other.enqueueTotalCount == enqueueTotalCount &&
        other.isCanceling == isCanceling &&
        other.isSyncing == isSyncing &&
        mapEquals(other.uploadItems, uploadItems) &&
        mapEquals(other.manualFailedUploadItems, manualFailedUploadItems) &&
        mapEquals(other.manualPendingUploadItems, manualPendingUploadItems) &&
        other.error == error;
  }

  @override
  int get hashCode {
    return totalCount.hashCode ^
        backupCount.hashCode ^
        remainderCount.hashCode ^
        processingCount.hashCode ^
        enqueueCount.hashCode ^
        enqueueTotalCount.hashCode ^
        isCanceling.hashCode ^
        isSyncing.hashCode ^
        uploadItems.hashCode ^
        manualFailedUploadItems.hashCode ^
        manualPendingUploadItems.hashCode ^
        error.hashCode;
  }
}

final driftBackupProvider = StateNotifierProvider<DriftBackupNotifier, DriftBackupState>((ref) {
  return DriftBackupNotifier(ref.watch(uploadServiceProvider), ref.watch(localAssetRepository));
});

class DriftBackupNotifier extends StateNotifier<DriftBackupState> {
  DriftBackupNotifier(this._uploadService, this._localAssetRepository)
    : super(
        const DriftBackupState(
          totalCount: 0,
          backupCount: 0,
          remainderCount: 0,
          processingCount: 0,
          enqueueCount: 0,
          enqueueTotalCount: 0,
          isCanceling: false,
          isSyncing: false,
          uploadItems: {},
          manualFailedUploadItems: {}, // pizcloud
          manualPendingUploadItems: {}, // pizcloud
          error: BackupError.none,
        ),
      ) {
    {
      _uploadService.taskStatusStream.listen(_handleTaskStatusUpdate);
      _uploadService.taskProgressStream.listen(_handleTaskProgressUpdate);
    }
    _hydrateManualFailedUploadItems(); // pizcloud
    _hydrateManualPendingUploadItems(); // pizcloud
    unawaited(Future<void>.delayed(const Duration(seconds: 1), () => reconcileManualPendingUploads())); // pizcloud
  }

  final UploadService _uploadService;
  final DriftLocalAssetRepository _localAssetRepository; // pizcloud
  StreamSubscription<TaskStatusUpdate>? _statusSubscription;
  StreamSubscription<TaskProgressUpdate>? _progressSubscription;
  Future<void>? _resumeBackupInFlight; // pizcloud: single-flight guard for resume backup
  Future<void>? _manualPendingReconcileInFlight; // pizcloud: single-flight guard for pending-manual reconciliation
  final Set<String> _manualRetryInFlight = <String>{}; // pizcloud
  final _logger = Logger("DriftBackupNotifier");

  /// Remove upload item from state
  void _removeUploadItem(String taskId) {
    if (state.uploadItems.containsKey(taskId)) {
      final updatedItems = Map<String, DriftUploadStatus>.from(state.uploadItems);
      updatedItems.remove(taskId);
      state = state.copyWith(uploadItems: updatedItems);
    }
  }

  // pizcloud
  void _hydrateManualFailedUploadItems() {
    final persisted = _readPersistedManualFailedUploadItems();
    if (persisted.isEmpty) {
      return;
    }
    state = state.copyWith(manualFailedUploadItems: persisted);
  }

  void _hydrateManualPendingUploadItems() {
    final persisted = _readPersistedManualPendingUploadItems();
    if (persisted.isEmpty) {
      return;
    }
    state = state.copyWith(manualPendingUploadItems: persisted);
  }

  Map<String, DriftManualFailedUploadItem> _readPersistedManualFailedUploadItems() {
    final raw = Store.tryGet(StoreKey.manualUploadFailedItems);
    if (raw == null || raw.isEmpty) {
      return <String, DriftManualFailedUploadItem>{};
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, DriftManualFailedUploadItem>{};
      }

      final output = <String, DriftManualFailedUploadItem>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final dynamic value = entry.value;
        if (value is Map<String, dynamic>) {
          output[key] = DriftManualFailedUploadItem.fromMap(value);
          continue;
        }
        if (value is Map) {
          output[key] = DriftManualFailedUploadItem.fromMap(
            value.map((entryKey, entryValue) => MapEntry(entryKey.toString(), entryValue)),
          );
        }
      }
      return output;
    } catch (_) {
      return <String, DriftManualFailedUploadItem>{};
    }
  }

  Map<String, DriftManualPendingUploadItem> _readPersistedManualPendingUploadItems() {
    final raw = Store.tryGet(StoreKey.manualUploadPendingItems);
    if (raw == null || raw.isEmpty) {
      return <String, DriftManualPendingUploadItem>{};
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, DriftManualPendingUploadItem>{};
      }

      final output = <String, DriftManualPendingUploadItem>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final dynamic value = entry.value;
        if (value is Map<String, dynamic>) {
          output[key] = DriftManualPendingUploadItem.fromMap(value);
          continue;
        }
        if (value is Map) {
          output[key] = DriftManualPendingUploadItem.fromMap(
            value.map((entryKey, entryValue) => MapEntry(entryKey.toString(), entryValue)),
          );
        }
      }
      return output;
    } catch (_) {
      return <String, DriftManualPendingUploadItem>{};
    }
  }

  Future<void> _persistManualFailedUploadItems(Map<String, DriftManualFailedUploadItem> items) async {
    if (items.isEmpty) {
      await Store.delete(StoreKey.manualUploadFailedItems);
      return;
    }

    final serialized = items.map((key, value) => MapEntry(key, value.toMap()));
    await Store.put(StoreKey.manualUploadFailedItems, jsonEncode(serialized));
  }

  Future<void> _persistManualPendingUploadItems(Map<String, DriftManualPendingUploadItem> items) async {
    if (items.isEmpty) {
      await Store.delete(StoreKey.manualUploadPendingItems);
      return;
    }

    final serialized = items.map((key, value) => MapEntry(key, value.toMap()));
    await Store.put(StoreKey.manualUploadPendingItems, jsonEncode(serialized));
  }

  void _upsertManualFailedUploadItem(DriftManualFailedUploadItem item) {
    final updatedItems = <String, DriftManualFailedUploadItem>{...state.manualFailedUploadItems, item.taskId: item};
    state = state.copyWith(manualFailedUploadItems: updatedItems);
    unawaited(_persistManualFailedUploadItems(updatedItems));
  }

  void _removeManualFailedUploadItem(String taskId) {
    if (!state.manualFailedUploadItems.containsKey(taskId)) {
      return;
    }
    final updatedItems = Map<String, DriftManualFailedUploadItem>.from(state.manualFailedUploadItems)..remove(taskId);
    state = state.copyWith(manualFailedUploadItems: updatedItems);
    unawaited(_persistManualFailedUploadItems(updatedItems));
  }

  void _removeManualPendingUploadItem(String taskId) {
    if (!state.manualPendingUploadItems.containsKey(taskId)) {
      return;
    }
    final updatedItems = Map<String, DriftManualPendingUploadItem>.from(state.manualPendingUploadItems)..remove(taskId);
    state = state.copyWith(manualPendingUploadItems: updatedItems);
    unawaited(_persistManualPendingUploadItems(updatedItems));
  }

  Future<void> stageManualPendingUploads(List<LocalAsset> localAssets) async {
    if (localAssets.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final updatedItems = <String, DriftManualPendingUploadItem>{...state.manualPendingUploadItems};
    for (final asset in localAssets) {
      // Old behavior did not persist manual-upload pending intent before dispatch.
      updatedItems[asset.id] = DriftManualPendingUploadItem(
        taskId: asset.id,
        filename: asset.name,
        fileSize: null,
        queuedAt: now,
      );
    }

    state = state.copyWith(manualPendingUploadItems: updatedItems);
    try {
      await _persistManualPendingUploadItems(updatedItems);
    } catch (error, stackTrace) {
      _logger.warning('Unable to persist pending manual upload items', error, stackTrace);
    }
  }

  Future<void> reconcileManualPendingUploads() {
    final runningReconcile = _manualPendingReconcileInFlight;
    if (runningReconcile != null) {
      return runningReconcile;
    }

    final startedReconcile = Future<void>.sync(_reconcileManualPendingUploadsInternal);
    _manualPendingReconcileInFlight = startedReconcile;
    return startedReconcile.whenComplete(() {
      if (identical(_manualPendingReconcileInFlight, startedReconcile)) {
        _manualPendingReconcileInFlight = null;
      }
    });
  }

  Future<void> _reconcileManualPendingUploadsInternal() async {
    final pendingItems = state.manualPendingUploadItems;
    if (pendingItems.isEmpty) {
      return;
    }

    try {
      final activeTasks = await _uploadService.getActiveTasks(kManualUploadGroup);
      final activeTaskIds = activeTasks.map((task) => task.taskId).toSet();

      final retainedPendingItems = <String, DriftManualPendingUploadItem>{};
      final updatedFailedItems = <String, DriftManualFailedUploadItem>{...state.manualFailedUploadItems};

      bool hasPendingChanged = false;
      bool hasFailedChanged = false;

      for (final entry in pendingItems.entries) {
        final taskId = entry.key;
        final pendingItem = entry.value;

        if (activeTaskIds.contains(taskId)) {
          retainedPendingItems[taskId] = pendingItem;
          continue;
        }

        hasPendingChanged = true;
        if (!updatedFailedItems.containsKey(taskId)) {
          updatedFailedItems[taskId] = DriftManualFailedUploadItem(
            taskId: taskId,
            filename: pendingItem.filename,
            error: kManualUploadInterruptedErrorCode,
            fileSize: pendingItem.fileSize,
            failedAt: DateTime.now(),
          );
          hasFailedChanged = true;
        }
      }

      if (!hasPendingChanged && !hasFailedChanged) {
        return;
      }

      state = state.copyWith(
        manualPendingUploadItems: retainedPendingItems,
        manualFailedUploadItems: updatedFailedItems,
      );

      await _persistManualPendingUploadItems(retainedPendingItems);
      if (hasFailedChanged) {
        await _persistManualFailedUploadItems(updatedFailedItems);
      }
    } catch (error, stackTrace) {
      _logger.warning('Unable to reconcile pending manual upload items', error, stackTrace);
    }
  }

  String? _resolveTaskError(TaskStatusUpdate update) {
    final exception = update.exception;
    if (exception != null && exception is TaskHttpException) {
      final message = tryJsonDecode(exception.description)?['message'] as String?;
      if (message != null) {
        final responseCode = exception.httpResponseCode;
        return "${exception.exceptionType}, response code $responseCode: $message";
      }
    }
    return update.exception?.toString();
  }

  int? _resolveCurrentFileSize(DriftUploadStatus? currentItem) {
    if (currentItem != null && currentItem.fileSize > 0) {
      return currentItem.fileSize;
    }
    return null;
  }
  // #pizcloud

  void _handleTaskStatusUpdate(TaskStatusUpdate update) {
    final taskId = update.task.taskId;

    switch (update.status) {
      case TaskStatus.complete:
        if (update.task.group == kManualUploadGroup) {
          _removeManualPendingUploadItem(taskId); // pizcloud
          _removeManualFailedUploadItem(taskId);
        } // pizcloud

        if (update.task.group == kBackupGroup) {
          if (update.responseStatusCode == 201) {
            state = state.copyWith(backupCount: state.backupCount + 1, remainderCount: state.remainderCount - 1);
          }
        }

        // Remove the completed task from the upload items
        if (state.uploadItems.containsKey(taskId)) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            _removeUploadItem(taskId);
          });
        }

      case TaskStatus.failed:
        // Ignore retry errors to avoid confusing users
        if (update.exception?.description == 'Delayed or retried enqueue failed') {
          _removeUploadItem(taskId);
          return;
        }

        final currentItem = state.uploadItems[taskId];
        // pizcloud
        if (update.task.group == kManualUploadGroup) {
          _removeManualPendingUploadItem(taskId); // pizcloud
          final failedItem = DriftManualFailedUploadItem(
            taskId: taskId,
            filename: currentItem?.filename ?? update.task.displayName,
            error: _resolveTaskError(update),
            fileSize: _resolveCurrentFileSize(currentItem),
            failedAt: DateTime.now(),
          );
          _upsertManualFailedUploadItem(failedItem);
          _removeUploadItem(taskId);
          _logger.fine("Manual upload failed for taskId: $taskId, exception: ${update.exception}");
          return;
        }
        //# pizcloud

        if (currentItem == null) {
          return;
        }

        final error = _resolveTaskError(update); // pizcloud

        state = state.copyWith(
          uploadItems: {
            ...state.uploadItems,
            taskId: currentItem.copyWith(isFailed: true, error: error),
          },
        );
        _logger.fine("Upload failed for taskId: $taskId, exception: ${update.exception}");
        break;

      case TaskStatus.canceled:
        if (update.task.group == kManualUploadGroup) {
          _removeManualPendingUploadItem(taskId);
        } // pizcloud
        _removeUploadItem(update.task.taskId);
        break;

      default:
        break;
    }
  }

  // pizcloud
  Future<ManualFailedUploadRetryResult> retryManualFailedUpload(String taskId) async {
    if (_manualRetryInFlight.contains(taskId)) {
      return ManualFailedUploadRetryResult.alreadyInProgress;
    }

    final failedItem = state.manualFailedUploadItems[taskId];
    if (failedItem == null) {
      return ManualFailedUploadRetryResult.itemNotFound;
    }

    final inProgressItem = state.uploadItems[taskId];
    if (inProgressItem != null && inProgressItem.isFailed != true && inProgressItem.progress < 1.0) {
      return ManualFailedUploadRetryResult.alreadyInProgress;
    }

    _manualRetryInFlight.add(taskId);
    try {
      final localAsset = await _localAssetRepository.getById(taskId);
      if (localAsset == null) {
        _upsertManualFailedUploadItem(failedItem.copyWith(failedAt: DateTime.now()));
        return ManualFailedUploadRetryResult.localAssetMissing;
      }

      // Old behavior had no retry action for a persisted failed list.
      // New behavior removes the failed row immediately once retry is dispatched.
      await stageManualPendingUploads([localAsset]); // pizcloud
      _removeManualFailedUploadItem(taskId);
      await _uploadService.manualBackup([localAsset]);
      return ManualFailedUploadRetryResult.started;
    } catch (error) {
      _removeManualPendingUploadItem(taskId); // pizcloud
      _upsertManualFailedUploadItem(failedItem.copyWith(error: error.toString(), failedAt: DateTime.now()));
      return ManualFailedUploadRetryResult.startFailed;
    } finally {
      _manualRetryInFlight.remove(taskId);
    }
  }

  Future<void> removeManualFailedUpload(String taskId) async {
    _removeManualFailedUploadItem(taskId);
  }
  // #pizcloud

  void _handleTaskProgressUpdate(TaskProgressUpdate update) {
    final taskId = update.task.taskId;
    final filename = update.task.displayName;
    final progress = update.progress;

    // pizcloud - old behavior only removed canceled rows and could re-add failed rows from progress stream.
    if (progress == kUploadStatusCanceled || progress == kUploadStatusFailed) {
      if (update.task.group == kManualUploadGroup) {
        _removeManualPendingUploadItem(taskId);
      } // pizcloud
      _removeUploadItem(taskId);
      return;
    }

    final currentItem = state.uploadItems[taskId];
    if (currentItem != null) {
      state = state.copyWith(
        uploadItems: {
          ...state.uploadItems,
          taskId: update.hasExpectedFileSize
              ? currentItem.copyWith(
                  progress: progress,
                  fileSize: update.expectedFileSize,
                  networkSpeedAsString: update.networkSpeedAsString,
                )
              : currentItem.copyWith(progress: progress),
        },
      );

      return;
    }

    state = state.copyWith(
      uploadItems: {
        ...state.uploadItems,
        taskId: DriftUploadStatus(
          taskId: taskId,
          filename: filename,
          progress: progress,
          fileSize: update.expectedFileSize,
          networkSpeedAsString: update.networkSpeedAsString,
        ),
      },
    );
  }

  Future<void> getBackupStatus(String userId) async {
    final counts = await _uploadService.getBackupCounts(userId);

    state = state.copyWith(
      totalCount: counts.total,
      backupCount: counts.total - counts.remainder,
      remainderCount: counts.remainder,
      processingCount: counts.processing,
    );
  }

  void updateError(BackupError error) async {
    state = state.copyWith(error: error);
  }

  void updateSyncing(bool isSyncing) async {
    state = state.copyWith(isSyncing: isSyncing);
  }

  Future<void> startBackup(String userId) {
    state = state.copyWith(error: BackupError.none);
    return _uploadService.startBackup(userId, _updateEnqueueCount);
  }

  void _updateEnqueueCount(EnqueueStatus status) {
    state = state.copyWith(enqueueCount: status.enqueueCount, enqueueTotalCount: status.totalCount);
  }

  Future<void> cancel() async {
    dPrint(() => "Canceling backup tasks...");
    state = state.copyWith(enqueueCount: 0, enqueueTotalCount: 0, isCanceling: true, error: BackupError.none);

    final activeTaskCount = await _uploadService.cancelBackup();

    if (activeTaskCount > 0) {
      dPrint(() => "$activeTaskCount tasks left, continuing to cancel...");
      await cancel();
    } else {
      dPrint(() => "All tasks canceled successfully.");
      // Clear all upload items when cancellation is complete
      state = state.copyWith(isCanceling: false, uploadItems: {});
    }
  }

  Future<void> handleBackupResume(String userId) {
    // pizcloud
    final runningResume = _resumeBackupInFlight;
    if (runningResume != null) {
      _logger.fine("Backup resume already in progress. Joining existing task.");
      return runningResume;
    }

    // Old behavior (kept for reference):
    // Future<void> handleBackupResume(String userId) async {
    //   _logger.info("Resuming backup tasks...");
    //   state = state.copyWith(error: BackupError.none);
    //   final tasks = await _uploadService.getActiveTasks(kBackupGroup);
    //   _logger.info("Found ${tasks.length} tasks");
    //
    //   if (tasks.isEmpty) {
    //     _logger.info("Start a new backup queue");
    //     return startBackup(userId);
    //   }
    //
    //   _logger.info("Tasks to resume: ${tasks.length}");
    //   return _uploadService.resumeBackup();
    // }

    final startedResume = Future<void>.sync(() => _handleBackupResumeInternal(userId));
    _resumeBackupInFlight = startedResume;

    return startedResume.whenComplete(() {
      if (identical(_resumeBackupInFlight, startedResume)) {
        _resumeBackupInFlight = null;
      }
    });
    // #pizcloud
  }

  Future<void> _handleBackupResumeInternal(String userId) async {
    _logger.info("Resuming backup tasks...");
    state = state.copyWith(error: BackupError.none);
    final tasks = await _uploadService.getActiveTasks(kBackupGroup);
    _logger.info("Found ${tasks.length} tasks");

    if (tasks.isEmpty) {
      // Start a new backup queue
      _logger.info("Start a new backup queue");
      return startBackup(userId);
    }

    _logger.info("Tasks to resume: ${tasks.length}");
    await _uploadService.resumeBackup(); // pizcloud

    if (_uploadService.hasPendingResumableSessions()) {
      _logger.info("Detected interrupted resumable sessions. Retrying direct resumable uploads.");
      await _uploadService.retryInterruptedResumableUploads(userId);
    } // pizcloud
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _progressSubscription?.cancel();
    super.dispose();
  }
}

final driftBackupCandidateProvider = FutureProvider.autoDispose<List<LocalAsset>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return [];
  }

  return ref.read(backupRepositoryProvider).getCandidates(user.id, onlyHashed: false);
});

final driftCandidateBackupAlbumInfoProvider = FutureProvider.autoDispose.family<List<LocalAlbum>, String>((
  ref,
  assetId,
) {
  return ref.read(localAssetRepository).getSourceAlbums(assetId, backupSelection: BackupSelection.selected);
});
