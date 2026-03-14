import 'dart:math' as math;

import 'download_queue.dart';
import 'grid_window.dart';

typedef GridPrefetchUrlResolver = String? Function(int row, int col);

class GridPrefetchController {
  GridPrefetchController({
    required this.preloadRowsAhead,
    required this.preloadRowsBehind,
    required this.maxRowExclusive,
    required this.queue,
    required this.resolveUrl,
  });

  final int preloadRowsAhead;
  final int preloadRowsBehind;
  final int Function() maxRowExclusive;
  final DownloadQueue queue;
  final GridPrefetchUrlResolver resolveUrl;

  void update(GridWindow window) {
    final Map<String, double> urlToPriority = <String, double>{};
    final int maxRows = maxRowExclusive();
    if (maxRows <= 0) {
      queue.setWanted(const <String>{});
      return;
    }

    final double centerRow = window.centerRow;
    final double centerCol = window.centerCol;
    final int startRow = math.max(0, window.firstRow - preloadRowsBehind);
    final int endRowExclusive = math.min(
      maxRows,
      window.lastRow + preloadRowsAhead,
    );
    final int startCol = window.firstCol;
    final int endColExclusive = window.lastCol;

    for (int row = startRow; row < endRowExclusive; row++) {
      for (int col = startCol; col < endColExclusive; col++) {
        final String? url = resolveUrl(row, col);
        if (url == null) continue;
        final double priority =
            (row - centerRow).abs() + (col - centerCol).abs();
        final double? existing = urlToPriority[url];
        if (existing == null || priority < existing) {
          urlToPriority[url] = priority;
        }
      }
    }

    queue.setWanted(urlToPriority.keys.toSet());
    queue.ensureMany(urlToPriority);
  }

  void disposeAll() {
    queue.setWanted(const <String>{});
  }
}
