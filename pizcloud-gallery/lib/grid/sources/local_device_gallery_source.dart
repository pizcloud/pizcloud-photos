import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../media_item.dart';
import '../piz_gallery_source.dart';
import 'local_device_media_uri.dart';

/// Loads media directly from the device gallery (PhotoManager).
class LocalDeviceGallerySource extends PizGallerySource {
  LocalDeviceGallerySource({
    this.initialLoadCount = 100,
    this.pageSize = 200,
    this.maxItems = 2000,
    this.requestPermissionOnLoad = true,
  });

  final int initialLoadCount;
  final int pageSize;
  final int maxItems;
  final bool requestPermissionOnLoad;
  final StreamController<List<MediaItem>> _updatesController =
      StreamController<List<MediaItem>>.broadcast();
  List<MediaItem> _items = const <MediaItem>[];
  bool _disposed = false;
  bool _backgroundRunning = false;
  int _loadToken = 0;

  @override
  Stream<List<MediaItem>> watchUpdates() => _updatesController.stream;

  @override
  Future<List<MediaItem>> loadInitial() async {
    final int token = ++_loadToken;
    final PermissionState permission = requestPermissionOnLoad
        ? await PhotoManager.requestPermissionExtend()
        : await PhotoManager.getPermissionState(
            requestOption: const PermissionRequestOption(),
          );
    if (_disposed || token != _loadToken || !permission.isAuth) {
      _items = const <MediaItem>[];
      return const <MediaItem>[];
    }

    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );
    if (_disposed || token != _loadToken || paths.isEmpty) {
      _items = const <MediaItem>[];
      return const <MediaItem>[];
    }

    final AssetPathEntity path = paths.first;
    final int total = await path.assetCountAsync;
    if (_disposed || token != _loadToken || total <= 0) {
      _items = const <MediaItem>[];
      return const <MediaItem>[];
    }
    final int cappedTotal = maxItems <= 0
        ? total
        : (maxItems < total ? maxItems : total);
    final int initialCount = initialLoadCount <= 0
        ? 1
        : (initialLoadCount < cappedTotal ? initialLoadCount : cappedTotal);

    final List<AssetEntity> initialAssets = await path.getAssetListRange(
      start: 0,
      end: initialCount,
    );
    if (_disposed || token != _loadToken) {
      return const <MediaItem>[];
    }
    _items = List<MediaItem>.unmodifiable(_toMediaItems(initialAssets));
    _emitUpdate();

    if (_items.length < cappedTotal) {
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          () => _loadRemainingInBackground(
            path: path,
            maxCount: cappedTotal,
            startOffset: _items.length,
            token: token,
          ),
        ),
      );
    }
    return _items;
  }

  Future<void> _loadRemainingInBackground({
    required AssetPathEntity path,
    required int maxCount,
    required int startOffset,
    required int token,
  }) async {
    if (_backgroundRunning || _disposed || token != _loadToken) {
      return;
    }
    _backgroundRunning = true;
    int offset = startOffset;
    try {
      while (!_disposed && token == _loadToken && offset < maxCount) {
        final int nextEnd = (offset + pageSize) < maxCount
            ? (offset + pageSize)
            : maxCount;
        final List<AssetEntity> assets = await path.getAssetListRange(
          start: offset,
          end: nextEnd,
        );
        if (_disposed || token != _loadToken || assets.isEmpty) {
          break;
        }
        final List<MediaItem> appended = _toMediaItems(assets);
        if (appended.isEmpty) {
          break;
        }
        _items = List<MediaItem>.unmodifiable(<MediaItem>[
          ..._items,
          ...appended,
        ]);
        offset = _items.length;
        _emitUpdate();
      }
    } finally {
      _backgroundRunning = false;
    }
  }

  List<MediaItem> _toMediaItems(List<AssetEntity> assets) {
    final List<MediaItem> output = <MediaItem>[];
    for (final AssetEntity asset in assets) {
      if (asset.type == AssetType.other || asset.id.isEmpty) {
        continue;
      }
      final MediaType mediaType = asset.type == AssetType.video
          ? MediaType.video
          : MediaType.photo;
      final int? width = asset.width > 0 ? asset.width : null;
      final int? height = asset.height > 0 ? asset.height : null;
      final Duration? duration =
          mediaType == MediaType.video && asset.duration > 0
          ? Duration(seconds: asset.duration)
          : null;
      output.add(
        MediaItem(
          id: 'local_${asset.id}',
          type: mediaType,
          sourceType: MediaSourceType.local,
          originalUrl: LocalDeviceMediaUri.buildOriginalUri(asset.id),
          previewUrl: LocalDeviceMediaUri.buildThumbUri(
            assetId: asset.id,
            edge: 600,
          ),
          width: width,
          height: height,
          thumbnails: MediaThumbnails(
            size100: LocalDeviceMediaUri.buildThumbUri(
              assetId: asset.id,
              edge: 100,
            ),
            size300: LocalDeviceMediaUri.buildThumbUri(
              assetId: asset.id,
              edge: 300,
            ),
            size600: LocalDeviceMediaUri.buildThumbUri(
              assetId: asset.id,
              edge: 600,
            ),
          ),
          localPath: null,
          duration: duration,
          createdAt: asset.createDateTime,
          addedAt: asset.modifiedDateTime,
        ),
      );
    }
    return output;
  }

  void _emitUpdate() {
    if (_disposed || _updatesController.isClosed) {
      return;
    }
    _updatesController.add(_items);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _loadToken += 1;
    if (!_updatesController.isClosed) {
      await _updatesController.close();
    }
  }
}
