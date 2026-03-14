import 'package:flutter/services.dart' show rootBundle;

import 'media_item.dart';

class MediaDataSource {
  static const String defaultSampleAssetPath =
      'assets/mock/picsum_media_sample.json';

  final List<MediaItem> items;

  MediaDataSource(List<MediaItem> values) : items = List.unmodifiable(values);

  int get length => items.length;
  bool get isEmpty => items.isEmpty;

  MediaItem? itemAtDataIndex(int dataIndex) {
    if (dataIndex < 0 || dataIndex >= items.length) return null;
    return items[dataIndex];
  }

  MediaItem? itemAtCellIndex({
    required int cellIndex,
    required int firstDataCellIndex,
  }) {
    final dataIndex = cellIndex - firstDataCellIndex;
    return itemAtDataIndex(dataIndex);
  }

  static Future<MediaDataSource> sample({
    String assetPath = defaultSampleAssetPath,
    int? limit,
  }) async {
    final jsonText = await rootBundle.loadString(assetPath);
    final parsed = MediaItem.listFromJsonString(jsonText);
    final values = switch (limit) {
      final int n when n > 0 && n < parsed.length => parsed.take(n).toList(),
      _ => parsed,
    };
    return MediaDataSource(values);
  }
}
