import 'package:flutter/material.dart';

import 'cell_data.dart';
import 'grid_cell.dart';
import 'grid_cell_pool.dart';
import 'grid_state.dart';
import 'grid_window.dart';
import 'lru_bytes_cache.dart';
import 'media_data_source.dart';
import 'media_hero_tag.dart';
import 'media_item.dart';
import 'sources/local_device_media_uri.dart';
import 'reuse_grid_cell.dart';

class GridVisibleCellsBuilder {
  final GridState grid;
  final MediaDataSource mediaDataSource;
  final GridCellPool cellPool;
  final bool showDebugOutOfRangeCells;
  final LruBytesCache bytesCache;

  GridVisibleCellsBuilder({
    required this.grid,
    required this.mediaDataSource,
    required this.cellPool,
    required this.showDebugOutOfRangeCells,
    required this.bytesCache,
  });

  Widget buildVisibleCells({
    required GridWindow window,
    required bool enableReuseCell,
    required bool lightweightMode,
    int? thumbEdgeOverride,
    void Function(int dataIndex, String? thumbUrl, String heroTag)?
    onDataIndexTap,
  }) {
    final List<Widget> children = <Widget>[];
    final double renderScale = grid.getCurrentScale();
    final int currentColCount = grid.currentColCount;
    final int targetColCount = grid.targetColCount;
    final bool preferTargetColCount = grid.scaleDirection != 0;
    final ({int first, int last}) renderCols = _resolveRenderCols(
      window: window,
      currentColCount: currentColCount,
    );
    final int renderFirstCol = renderCols.first;
    final int renderLastCol = renderCols.last;

    if (renderLastCol <= renderFirstCol) {
      if (enableReuseCell) {
        cellPool.releaseMissing(<String>{});
      } else if (cellPool.hasBufferedCells) {
        cellPool.clear();
      }
      return const SizedBox.shrink();
    }

    if (lightweightMode) {
      return IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(grid.defaultColCount * grid.cellSize, grid.gridHeight()),
            painter: _LightweightGridPainter(
              firstRow: window.firstRow,
              lastRow: window.lastRow,
              firstCol: renderFirstCol,
              lastCol: renderLastCol,
              baseRow: grid.baseRow,
              targetColCount: targetColCount,
              targetBaseCells: grid.baseCells[targetColCount],
              totalDataCells: grid.totalDataCells,
              cellSize: grid.cellSize,
            ),
          ),
        ),
      );
    }

    if (!enableReuseCell) {
      if (cellPool.hasBufferedCells) {
        cellPool.clear();
      }
      for (int row = window.firstRow; row < window.lastRow; row++) {
        final int logicalRow = grid.baseRow + row;
        for (int col = renderFirstCol; col < renderLastCol; col++) {
          final int logicalIndex = logicalRow * grid.defaultColCount + col;
          final String key = '$logicalIndex';
          final CellData? cell = _buildCellData(
            logicalRow: logicalRow,
            col: col,
            logicalIndex: logicalIndex,
            renderScale: renderScale,
            currentColCount: currentColCount,
            targetColCount: targetColCount,
            preferTargetColCount: preferTargetColCount,
            thumbEdgeOverride: thumbEdgeOverride,
          );
          if (cell == null) continue;
          children.add(
            Positioned(
              key: ValueKey(key),
              left: col * grid.cellSize,
              top: row * grid.cellSize,
              child: GridCell(
                data: cell,
                size: grid.cellSize,
                bytesCache: bytesCache,
                onTap:
                    cell.dataIndex == null ||
                        cell.mediaItem == null ||
                        onDataIndexTap == null
                    ? null
                    : () => onDataIndexTap(
                        cell.dataIndex!,
                        cell.thumbUrl,
                        mediaGridCellHeroTag(
                          mediaId: cell.mediaItem!.id,
                          cellId: cell.id,
                        ),
                      ),
              ),
            ),
          );
        }
      }
      return Stack(children: children);
    }

    final Set<String> needed = <String>{};
    for (int row = window.firstRow; row < window.lastRow; row++) {
      final int logicalRow = grid.baseRow + row;
      for (int col = renderFirstCol; col < renderLastCol; col++) {
        final int logicalIndex = logicalRow * grid.defaultColCount + col;
        final String key = '$logicalIndex';
        final CellData? cell = _buildCellData(
          logicalRow: logicalRow,
          col: col,
          logicalIndex: logicalIndex,
          renderScale: renderScale,
          currentColCount: currentColCount,
          targetColCount: targetColCount,
          preferTargetColCount: preferTargetColCount,
          thumbEdgeOverride: thumbEdgeOverride,
        );
        if (cell == null) continue;

        needed.add(key);
        final ValueNotifier<CellData>? existing = cellPool.activeOf(key);
        final ValueNotifier<CellData> notifier =
            existing ?? cellPool.ensureActive(key, cell);
        if (existing != null && !existing.value.sameVisual(cell)) {
          existing.value = cell;
        }

        children.add(
          Positioned(
            key: ValueKey(key),
            left: col * grid.cellSize,
            top: row * grid.cellSize,
            child: ReuseGridCell(
              notifier: notifier,
              size: grid.cellSize,
              bytesCache: bytesCache,
              onDataIndexTap: onDataIndexTap,
            ),
          ),
        );
      }
    }

    cellPool.releaseMissing(needed);

    return Stack(children: children);
  }

  ({int first, int last}) _resolveRenderCols({
    required GridWindow window,
    required int currentColCount,
  }) {
    int first = window.firstCol;
    int last = window.lastCol;

    // When scale has settled, render exactly columns inside current viewport.
    if (grid.scaleDirection == 0 && !grid.isScalingNotifier.value) {
      final int safeCurrentColCount = currentColCount <= 0
          ? 1
          : currentColCount;
      final int maxFirstCol = (grid.defaultColCount - safeCurrentColCount)
          .clamp(0, grid.defaultColCount);
      final int viewportFirstCol = grid.viewportFirstCol.clamp(0, maxFirstCol);
      final int viewportLastCol = (viewportFirstCol + safeCurrentColCount)
          .clamp(0, grid.defaultColCount);
      first = first.clamp(viewportFirstCol, viewportLastCol);
      last = last.clamp(viewportFirstCol, viewportLastCol);
    }

    if (last < first) {
      last = first;
    }
    return (first: first, last: last);
  }

  CellData? _buildCellData({
    required int logicalRow,
    required int col,
    required int logicalIndex,
    required double renderScale,
    required int currentColCount,
    required int targetColCount,
    required bool preferTargetColCount,
    required int? thumbEdgeOverride,
  }) {
    final int index =
        logicalRow * targetColCount + col - grid.baseCells[targetColCount];
    if (index < 0 || index >= grid.totalDataCells) {
      if (!showDebugOutOfRangeCells) return null;
      final String debugText = index < 0
          ? '$index'
          : '+${index - grid.totalDataCells + 1}';
      return CellData(
        id: '$logicalIndex',
        text: debugText,
        renderScale: renderScale,
        currentColCount: currentColCount,
        targetColCount: targetColCount,
        preferTargetColCount: preferTargetColCount,
      );
    }

    final mediaItem = mediaDataSource.itemAtDataIndex(index);
    final int? thumbEdge = mediaItem == null
        ? null
        : ((thumbEdgeOverride != null && thumbEdgeOverride > 0)
              ? thumbEdgeOverride
              : mediaItem.thumbnails.adaptiveEdge(
                  cellSize: grid.cellSize,
                  scale: renderScale,
                  currentColCount: currentColCount,
                  targetColCount: targetColCount,
                  preferTargetColCount: preferTargetColCount,
                ));
    final String? thumbUrl = (mediaItem != null && thumbEdge != null)
        ? _resolveThumbUrlForEdge(mediaItem, thumbEdge)
        : null;
    return CellData(
      id: '$logicalIndex',
      text: '$index',
      dataIndex: index,
      mediaItem: mediaItem,
      thumbEdge: thumbEdge,
      thumbUrl: thumbUrl,
      renderScale: renderScale,
      currentColCount: currentColCount,
      targetColCount: targetColCount,
      preferTargetColCount: preferTargetColCount,
    );
  }

  String? _resolveThumbUrlForEdge(MediaItem mediaItem, int edge) {
    if (mediaItem.isLocal && edge > 0) {
      final String? assetId =
          LocalDeviceMediaUri.parseOriginalAssetId(mediaItem.originalUrl) ??
          LocalDeviceMediaUri.parseThumbUri(
            mediaItem.previewUrl ?? '',
          )?.assetId ??
          LocalDeviceMediaUri.parseThumbUri(
            mediaItem.thumbnails.size100,
          )?.assetId;
      if (assetId != null && assetId.isNotEmpty) {
        return LocalDeviceMediaUri.buildThumbUri(assetId: assetId, edge: edge);
      }
    }
    return mediaItem.pickGridThumbForEdge(edge);
  }
}

class _LightweightGridPainter extends CustomPainter {
  const _LightweightGridPainter({
    required this.firstRow,
    required this.lastRow,
    required this.firstCol,
    required this.lastCol,
    required this.baseRow,
    required this.targetColCount,
    required this.targetBaseCells,
    required this.totalDataCells,
    required this.cellSize,
  });

  final int firstRow;
  final int lastRow;
  final int firstCol;
  final int lastCol;
  final int baseRow;
  final int targetColCount;
  final int targetBaseCells;
  final int totalDataCells;
  final double cellSize;

  static const Color _cellColor = Color(0xFF1B1B1B);
  static const double _cellInset = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = _cellColor;
    final double paintedSize = (cellSize - (_cellInset * 2)).clamp(
      0.0,
      cellSize,
    );
    for (int row = firstRow; row < lastRow; row++) {
      final int logicalRow = baseRow + row;
      final double top = row * cellSize + _cellInset;
      for (int col = firstCol; col < lastCol; col++) {
        final int index = logicalRow * targetColCount + col - targetBaseCells;
        if (index < 0 || index >= totalDataCells) {
          continue;
        }
        final double left = col * cellSize + _cellInset;
        canvas.drawRect(
          Rect.fromLTWH(left, top, paintedSize, paintedSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LightweightGridPainter oldDelegate) {
    return firstRow != oldDelegate.firstRow ||
        lastRow != oldDelegate.lastRow ||
        firstCol != oldDelegate.firstCol ||
        lastCol != oldDelegate.lastCol ||
        baseRow != oldDelegate.baseRow ||
        targetColCount != oldDelegate.targetColCount ||
        targetBaseCells != oldDelegate.targetBaseCells ||
        totalDataCells != oldDelegate.totalDataCells ||
        cellSize != oldDelegate.cellSize;
  }
}
