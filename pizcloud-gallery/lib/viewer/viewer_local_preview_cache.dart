import 'dart:collection';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';
import 'package:pizcloud_gallery/grid/sources/local_device_media_uri.dart';

class ViewerLocalPreviewCache {
  static const int _maxEntries = 220;
  static final LinkedHashMap<String, Uint8List> _bytesBySource =
      LinkedHashMap<String, Uint8List>();

  static String? pickPreviewSource(MediaItem item) {
    final List<String?> candidates = <String?>[
      item.previewUrl,
      item.thumbnails.size600,
      item.thumbnails.size300,
      item.thumbnails.size100,
    ];
    for (final String? candidate in candidates) {
      final String value = candidate?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static Uint8List? peek(String source) {
    final Uint8List? bytes = _bytesBySource.remove(source);
    if (bytes == null) {
      return null;
    }
    _bytesBySource[source] = bytes;
    return bytes;
  }

  static void put(String source, Uint8List bytes) {
    if (source.isEmpty || bytes.isEmpty) {
      return;
    }
    _bytesBySource.remove(source);
    _bytesBySource[source] = bytes;
    while (_bytesBySource.length > _maxEntries) {
      _bytesBySource.remove(_bytesBySource.keys.first);
    }
  }

  static Future<Uint8List?> resolve(String source) async {
    final ({String assetId, int edge})? thumbUri =
        LocalDeviceMediaUri.parseThumbUri(source);
    if (thumbUri == null) {
      return null;
    }
    try {
      final AssetEntity? asset = await AssetEntity.fromId(thumbUri.assetId);
      if (asset == null) {
        return null;
      }
      final int edge = thumbUri.edge <= 0 ? 600 : thumbUri.edge;
      return asset.thumbnailDataWithSize(
        ThumbnailSize.square(edge),
        quality: 86,
      );
    } catch (_) {
      return null;
    }
  }
}
