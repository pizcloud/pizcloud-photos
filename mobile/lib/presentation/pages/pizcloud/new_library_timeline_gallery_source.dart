import 'dart:async';
import 'dart:math' as math;

import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

import 'new_library_media_mapper.dart';

class TimelineGallerySource extends PizGallerySource {
  TimelineGallerySource({required TimelineQuery query, this.batchSize = 600})
    : _assetSource = query.assetSource,
      _bucketSource = query.bucketSource;

  final TimelineAssetSource _assetSource;
  final TimelineBucketSource _bucketSource;
  final int batchSize;
  final Map<String, BaseAsset> _assetsByMediaItemId = <String, BaseAsset>{};

  bool _disposed = false;

  BaseAsset? findAssetByMediaItemId(String mediaItemId) {
    return _assetsByMediaItemId[mediaItemId];
  }

  @override
  Future<List<MediaItem>> loadInitial() async {
    final buckets = await _bucketSource().first;
    return _loadFromBuckets(buckets);
  }

  @override
  Stream<List<MediaItem>> watchUpdates() {
    return _bucketSource().asyncMap(_loadFromBuckets);
  }

  Future<List<MediaItem>> _loadFromBuckets(List<Bucket> buckets) async {
    if (_disposed) {
      return const <MediaItem>[];
    }

    final totalAssets = buckets.fold<int>(0, (sum, bucket) => sum + bucket.assetCount);
    if (totalAssets <= 0) {
      return const <MediaItem>[];
    }

    final items = <MediaItem>[];
    final seenIds = <String>{};
    final nextAssetsByMediaItemId = <String, BaseAsset>{};
    var offset = 0;
    final safeBatchSize = batchSize <= 0 ? 600 : batchSize;

    while (!_disposed && offset < totalAssets) {
      final count = math.min(safeBatchSize, totalAssets - offset);
      final assets = await _assetSource(offset, count);
      if (assets.isEmpty) {
        break;
      }

      for (final asset in assets) {
        final item = mapTimelineAssetToMediaItem(asset);
        if (item != null && seenIds.add(item.id)) {
          items.add(item);
          nextAssetsByMediaItemId[item.id] = asset;
        }
      }

      offset += assets.length;
    }

    _assetsByMediaItemId
      ..clear()
      ..addAll(nextAssetsByMediaItemId);
    return List<MediaItem>.unmodifiable(items);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _assetsByMediaItemId.clear();
  }
}
