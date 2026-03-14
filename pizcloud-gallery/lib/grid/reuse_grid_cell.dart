import 'package:flutter/material.dart';
import 'cell_data.dart';
import 'grid_cell.dart';
import 'lru_bytes_cache.dart';
import 'media_hero_tag.dart';

class ReuseGridCell extends StatelessWidget {
  final ValueNotifier<CellData> notifier;
  final double size;
  final LruBytesCache bytesCache;
  final void Function(int dataIndex, String? thumbUrl, String heroTag)?
  onDataIndexTap;

  const ReuseGridCell({
    super.key,
    required this.notifier,
    required this.size,
    required this.bytesCache,
    this.onDataIndexTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CellData>(
      valueListenable: notifier,
      builder: (context, data, _) {
        return GridCell(
          data: data,
          size: size,
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
        );
      },
    );
  }
}
