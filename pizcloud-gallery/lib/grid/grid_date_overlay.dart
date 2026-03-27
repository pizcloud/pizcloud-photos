import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'grid_appearance_config.dart';
import 'grid_state.dart';
import 'grid_state_helper.dart';
import 'media_data_source.dart';
import 'media_item.dart';

typedef GridDateOverlayTextBuilder = String? Function(MediaItem item);

class GridDateOverlay extends StatefulWidget {
  const GridDateOverlay({
    super.key,
    required this.grid,
    required this.mediaDataSource,
    this.textBuilder,
    this.preferAddedAt = false,
  });

  final GridState grid;
  final MediaDataSource mediaDataSource;
  final GridDateOverlayTextBuilder? textBuilder;
  final bool preferAddedAt;

  @override
  State<GridDateOverlay> createState() => _GridDateOverlayState();
}

class _GridDateOverlayState extends State<GridDateOverlay> {
  int _lastDataIndex = -1;
  String? _cachedLabel;

  @override
  void didUpdateWidget(covariant GridDateOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textBuilder != widget.textBuilder ||
        oldWidget.mediaDataSource != widget.mediaDataSource ||
        oldWidget.preferAddedAt != widget.preferAddedAt) {
      _lastDataIndex = -1;
      _cachedLabel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final GridAppearancePalette palette = GridAppearancePalette.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.grid.scrollOffset,
        widget.grid.transformController,
      ]),
      builder: (context, child) {
        final String? label = _resolveLabel();
        if (label == null || label.isEmpty) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.fpsBadgeBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.fpsBadgeText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _resolveLabel() {
    if (widget.mediaDataSource.isEmpty) {
      _lastDataIndex = -1;
      _cachedLabel = null;
      return null;
    }

    final int dataIndex = _resolveTopDataIndex();
    if (dataIndex < 0 || dataIndex >= widget.mediaDataSource.length) {
      return null;
    }
    if (dataIndex == _lastDataIndex && _cachedLabel != null) {
      return _cachedLabel;
    }

    _lastDataIndex = dataIndex;
    final MediaItem? item = widget.mediaDataSource.itemAtDataIndex(dataIndex);
    if (item == null) {
      _cachedLabel = null;
      return null;
    }
    final DateTime? overlayDate = _resolveOverlayDate(item);
    final MediaItem displayItem = _itemWithOverlayDate(item, overlayDate);
    _cachedLabel =
        widget.textBuilder?.call(displayItem) ?? _defaultText(overlayDate);
    return _cachedLabel;
  }

  int _resolveTopDataIndex() {
    final GridState grid = widget.grid;
    final int length = widget.mediaDataSource.length;
    if (length <= 0) {
      return -1;
    }
    if (!GridStateHelper.isValidCellSize(grid.cellSize)) {
      return 0;
    }

    final int cols = grid.currentColCount <= 0 ? 1 : grid.currentColCount;
    final int maxFirstCol = math.max(0, grid.defaultColCount - cols);
    final Matrix4 matrix = grid.transformController.value;
    final double scale = GridStateHelper.safeScale(matrix);
    final double tx = GridStateHelper.translateX(matrix);
    final double leftX = -tx / scale;
    final int leftCol = (leftX / grid.cellSize).round().clamp(0, maxFirstCol);
    final int firstCol = grid.computeFirstCellCol(
      colCount: cols,
      viewportCol: leftCol,
    );
    final int leadingSlots = (firstCol - leftCol).clamp(0, cols - 1).toInt();

    final double rawTopRow = grid.currentRealTopRow(
      colCount: cols,
      leftCol: leftCol,
    );
    final int dataRows = grid.realDataRowCount(colCount: cols);

    int topRow = rawTopRow.isFinite ? rawTopRow.floor() : 0;
    if (topRow < 0) {
      topRow = 0;
    } else if (dataRows > 0 && topRow >= dataRows) {
      topRow = dataRows - 1;
    }

    int dataIndex = topRow * cols - leadingSlots;
    if (dataIndex < 0) {
      dataIndex = 0;
    } else if (dataIndex >= length) {
      dataIndex = length - 1;
    }
    return dataIndex;
  }

  DateTime? _resolveOverlayDate(MediaItem item) {
    if (widget.preferAddedAt) {
      // final DateTime? sourceDate = item.createdAt ?? item.addedAt;
      return item.addedAt ?? item.createdAt ?? item.createdLocalAt; // new
    }
    return item.createdLocalAt ?? item.createdAt ?? item.addedAt; // new
  }

  MediaItem _itemWithOverlayDate(MediaItem item, DateTime? overlayDate) {
    if (overlayDate == null) {
      return item;
    }
    return MediaItem(
      id: item.id,
      type: item.type,
      sourceType: item.sourceType,
      originalUrl: item.originalUrl,
      previewUrl: item.previewUrl,
      width: item.width,
      height: item.height,
      thumbnails: item.thumbnails,
      localPath: item.localPath,
      duration: item.duration,
      createdAt: overlayDate,
      createdLocalAt: overlayDate, // new
      addedAt: overlayDate,
    );
  }

  String? _defaultText(DateTime? sourceDate) {
    if (sourceDate == null) {
      return null;
    }
    final DateTime date = sourceDate.toLocal();
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
