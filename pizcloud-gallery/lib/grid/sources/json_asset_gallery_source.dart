import 'package:flutter/services.dart';

import '../media_item.dart';
import '../piz_gallery_source.dart';

/// Snapshot source backed by a local JSON asset.
class JsonAssetGallerySource extends PizGallerySource {
  JsonAssetGallerySource({
    required this.assetPath,
    AssetBundle? bundle,
    this.limit,
  }) : _bundle = bundle ?? rootBundle;

  final String assetPath;
  final AssetBundle _bundle;
  final int? limit;
  final Set<String> _removedItemIds = <String>{};

  @override
  Future<List<MediaItem>> loadInitial() async {
    final String jsonText = await _bundle.loadString(assetPath);
    final List<MediaItem> parsed = MediaItem.listFromJsonString(jsonText)
        .where((MediaItem item) => !_removedItemIds.contains(item.id))
        .toList(growable: false);
    final int? max = limit;
    if (max != null && max > 0 && max < parsed.length) {
      return parsed.take(max).toList(growable: false);
    }
    return parsed;
  }

  @override
  Future<void> removeItem(MediaItem item) async {
    _removedItemIds.add(item.id);
  }
}
