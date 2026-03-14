import 'dart:async';

import 'package:pizcloud_gallery/media/media_models.dart' as media;
import 'package:pizcloud_gallery/media/media_repository.dart';

import '../media_item.dart';
import '../piz_gallery_source.dart';
import 'local_device_media_uri.dart';

/// SQLite-backed local gallery source.
///
/// This source only reads indexed data from DB and emits snapshots.
/// It does not scan device media by itself.
class LocalDatabaseGallerySource extends PizGallerySource {
  LocalDatabaseGallerySource({
    MediaRepository? repository,
    this.initialLoadCount = 120,
    this.maxItems,
    this.updateDebounce = const Duration(milliseconds: 120),
  }) : _repository = repository ?? MediaRepository();

  final MediaRepository _repository;
  final int initialLoadCount;
  final int? maxItems;
  final Duration updateDebounce;

  final StreamController<List<MediaItem>> _updatesController =
      StreamController<List<MediaItem>>.broadcast();
  Timer? _emitDebounceTimer;
  List<MediaItem> _latestItems = const <MediaItem>[];
  final Set<String> _removedItemIds = <String>{};
  int _currentEmitLimit = 1;
  int _scheduledScannedCount = 0;
  bool _disposed = false;

  @override
  Future<List<MediaItem>> loadInitial() async {
    _currentEmitLimit = _safePositive(initialLoadCount);
    final List<MediaItem> initial = await _readIndexedItems(
      limit: _currentEmitLimit,
    );
    _latestItems = initial;
    return initial;
  }

  @override
  Stream<List<MediaItem>> watchUpdates() {
    // Replay the latest snapshot so subscribers don't miss updates emitted
    // before they attached (e.g. scan completed during grid bootstrap).
    return Stream<List<MediaItem>>.multi((controller) {
      if (_disposed || controller.isClosed) {
        return;
      }
      controller.add(_latestItems);
      final StreamSubscription<List<MediaItem>> subscription =
          _updatesController.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = () => subscription.cancel();
    });
  }

  /// Schedules a debounced DB refresh.
  void scheduleRefresh({required int scannedCount}) {
    if (_disposed) {
      return;
    }
    _scheduledScannedCount = scannedCount;
    _emitDebounceTimer?.cancel();
    _emitDebounceTimer = Timer(updateDebounce, () {
      unawaited(_refreshScheduled());
    });
  }

  Future<void> _refreshScheduled() async {
    try {
      await refresh(scannedCount: _scheduledScannedCount);
    } catch (error, stackTrace) {
      emitError(error, stackTrace);
    }
  }

  /// Reads the newest snapshot from DB and emits if changed.
  Future<void> refresh({bool force = false, int? scannedCount}) async {
    if (_disposed) {
      return;
    }
    final int? limit = _nextEmitLimit(force: force, scannedCount: scannedCount);
    final List<MediaItem> next = await _readIndexedItems(limit: limit);
    if (limit == null) {
      // Keep in-memory limit aligned with full snapshots to avoid a later
      // incremental refresh shrinking back to the initial limit.
      _currentEmitLimit = next.length;
    }
    if (_disposed) {
      return;
    }
    if (!force && _hasSameIds(_latestItems, next)) {
      return;
    }
    _latestItems = next;
    if (!_updatesController.isClosed) {
      _updatesController.add(next);
    }
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    if (_disposed || _updatesController.isClosed) {
      return;
    }
    _updatesController.addError(error, stackTrace);
  }

  int? _nextEmitLimit({required bool force, required int? scannedCount}) {
    final int? maxLimit = _normalizedMaxLimit;
    if (force) {
      if (maxLimit == null) {
        return null;
      }
      _currentEmitLimit = maxLimit;
      return maxLimit;
    }
    final int scanned = scannedCount ?? 0;
    final int next = scanned > _currentEmitLimit ? scanned : _currentEmitLimit;
    if (maxLimit == null) {
      _currentEmitLimit = next;
      return next;
    }
    _currentEmitLimit = next > maxLimit ? maxLimit : next;
    return _currentEmitLimit;
  }

  Future<List<MediaItem>> _readIndexedItems({required int? limit}) async {
    if (_disposed) {
      return const <MediaItem>[];
    }
    if (limit != null && limit <= 0) {
      return const <MediaItem>[];
    }
    final List<media.MediaItem> indexed = await _repository.fetchLocalItems(
      limit: limit,
      newestFirst: true,
    );
    final Iterable<MediaItem> mapped = indexed.map(_toGridItem);
    if (_removedItemIds.isEmpty) {
      return mapped.toList(growable: false);
    }
    return mapped
        .where((MediaItem item) => !_removedItemIds.contains(item.id))
        .toList(growable: false);
  }

  Future<int> countIndexedItemsInDb({MediaType? type}) {
    return _repository.countLocalItems(type: _toRepositoryType(type));
  }

  media.MediaType? _toRepositoryType(MediaType? type) {
    if (type == null) {
      return null;
    }
    return type == MediaType.video
        ? media.MediaType.video
        : media.MediaType.photo;
  }

  MediaItem _toGridItem(media.MediaItem value) {
    final String localId = value.localId ?? '';
    final MediaType type = value.type == media.MediaType.video
        ? MediaType.video
        : MediaType.photo;
    final int? width = (value.width != null && value.width! > 0)
        ? value.width
        : null;
    final int? height = (value.height != null && value.height! > 0)
        ? value.height
        : null;
    final Duration? duration =
        value.durationMs == null || value.durationMs! <= 0
        ? null
        : Duration(milliseconds: value.durationMs!);
    final DateTime? createdAt = value.createdAt ?? value.modifiedAt;
    final DateTime? addedAt = value.modifiedAt ?? value.createdAt;
    return MediaItem(
      id: 'local_$localId',
      type: type,
      sourceType: MediaSourceType.local,
      originalUrl: LocalDeviceMediaUri.buildOriginalUri(localId),
      previewUrl: LocalDeviceMediaUri.buildThumbUri(
        assetId: localId,
        edge: 300,
      ),
      width: width,
      height: height,
      thumbnails: MediaThumbnails(
        size100: LocalDeviceMediaUri.buildThumbUri(assetId: localId, edge: 100),
        size300: LocalDeviceMediaUri.buildThumbUri(assetId: localId, edge: 300),
        size600: LocalDeviceMediaUri.buildThumbUri(assetId: localId, edge: 600),
      ),
      localPath: null,
      duration: duration,
      createdAt: createdAt,
      addedAt: addedAt,
    );
  }

  bool _hasSameIds(List<MediaItem> left, List<MediaItem> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int i = 0; i < left.length; i++) {
      if (left[i].id != right[i].id) {
        return false;
      }
    }
    return true;
  }

  int _safePositive(int value) {
    if (value <= 0) {
      return 1;
    }
    return value;
  }

  int? get _normalizedMaxLimit {
    final int? value = maxItems;
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _emitDebounceTimer?.cancel();
    _emitDebounceTimer = null;
    if (!_updatesController.isClosed) {
      await _updatesController.close();
    }
  }

  @override
  Future<void> removeItem(MediaItem item) async {
    if (_disposed) {
      return;
    }
    final bool added = _removedItemIds.add(item.id);
    if (!added) {
      return;
    }
    final int previousLength = _latestItems.length;
    _latestItems = List<MediaItem>.unmodifiable(
      _latestItems.where((MediaItem value) => value.id != item.id),
    );
    if (_latestItems.length == previousLength || _updatesController.isClosed) {
      return;
    }
    _updatesController.add(_latestItems);
  }
}
