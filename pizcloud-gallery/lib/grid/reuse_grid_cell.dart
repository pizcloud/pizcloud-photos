import 'package:flutter/material.dart';
import 'cell_data.dart';
import 'grid_cell.dart';
import 'lru_bytes_cache.dart';
import 'media_hero_tag.dart';

class ReuseGridCell extends StatelessWidget {
  final ValueNotifier<CellData> notifier;
  final double size;
  final double viewScale; // new
  final LruBytesCache bytesCache;
  final void Function(int dataIndex, String? thumbUrl, String heroTag)?
  onDataIndexTap;
  final void Function(int dataIndex)? onDataIndexLongPress; // new

  const ReuseGridCell({
    super.key,
    required this.notifier,
    required this.size,
    this.viewScale = 1.0, // new
    required this.bytesCache,
    this.onDataIndexTap,
    this.onDataIndexLongPress, // new
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CellData>(
      valueListenable: notifier,
      builder: (context, data, _) {
        return GridCell(
          data: data,
          size: size,
          viewScale: viewScale,
          bytesCache: bytesCache,
          onTap:
              data.dataIndex == null ||
                  data.mediaItem == null ||
                  onDataIndexTap == null
              ? null
              : () => onDataIndexTap!(
                  data.dataIndex!,
                  data.thumbUrl,
                  mediaGridCellHeroTag(
                    mediaId: data.mediaItem!.id,
                    cellId: data.id,
                  ),
                ),
          onLongPress: data.dataIndex == null || onDataIndexLongPress == null
              ? null
              : () => onDataIndexLongPress!(data.dataIndex!), // new
        );
      },
    );
  }
}
