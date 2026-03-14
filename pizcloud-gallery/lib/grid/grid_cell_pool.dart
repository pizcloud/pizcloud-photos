import 'package:flutter/foundation.dart';

import 'cell_data.dart';

class GridCellPool {
  final Map<String, ValueNotifier<CellData>> _active =
      <String, ValueNotifier<CellData>>{};
  final List<ValueNotifier<CellData>> _pool = <ValueNotifier<CellData>>[];

  bool get hasBufferedCells => _active.isNotEmpty || _pool.isNotEmpty;
  int get activeCount => _active.length;
  int get pooledCount => _pool.length;

  ValueNotifier<CellData>? activeOf(String key) => _active[key];

  ValueNotifier<CellData> ensureActive(String key, CellData data) {
    final ValueNotifier<CellData>? existing = _active[key];
    if (existing != null) return existing;

    final ValueNotifier<CellData> notifier;
    if (_pool.isNotEmpty) {
      notifier = _pool.removeLast();
      notifier.value = data;
    } else {
      notifier = ValueNotifier<CellData>(data);
    }
    _active[key] = notifier;
    return notifier;
  }

  void release(String key) {
    final ValueNotifier<CellData>? notifier = _active.remove(key);
    if (notifier != null) {
      _pool.add(notifier);
    }
  }

  void releaseMissing(Set<String> neededKeys) {
    final List<String> removeKeys = _active.keys
        .where((String key) => !neededKeys.contains(key))
        .toList();
    for (final String key in removeKeys) {
      release(key);
    }
  }

  void clear() {
    for (final ValueNotifier<CellData> notifier in _active.values) {
      notifier.dispose();
    }
    _active.clear();

    for (final ValueNotifier<CellData> notifier in _pool) {
      notifier.dispose();
    }
    _pool.clear();
  }
}
