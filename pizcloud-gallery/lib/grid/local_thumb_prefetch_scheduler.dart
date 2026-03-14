import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

class LocalThumbPrefetchTask {
  const LocalThumbPrefetchTask({
    required this.cacheKey,
    required this.dataIndex,
    required this.assetId,
    required this.edge,
    required this.isVideo,
    required this.priority,
    required this.isInViewport,
  });

  final String cacheKey;
  final int dataIndex;
  final String assetId;
  final int edge;
  final bool isVideo;
  final double priority;
  final bool isInViewport;
}

typedef LocalThumbPrefetchLoader =
    Future<Uint8List?> Function(LocalThumbPrefetchTask task);
typedef LocalThumbPrefetchStore =
    void Function(LocalThumbPrefetchTask task, Uint8List bytes);
typedef LocalThumbPrefetchKeyPredicate = bool Function(String cacheKey);
typedef LocalThumbPrefetchMarkFailed = void Function(String cacheKey);

class LocalThumbPrefetchScheduler {
  LocalThumbPrefetchScheduler({
    required this.defaultMaxConcurrent,
    required this.loader,
    required this.store,
    required this.isCached,
    required this.isFailed,
    required this.markFailed,
    this.debugEnabled = false,
    this.debugName = 'local_thumb_prefetch',
    this.debugLogThrottleMs = 120,
  }) : _maxConcurrent = defaultMaxConcurrent;

  final int defaultMaxConcurrent;
  final LocalThumbPrefetchLoader loader;
  final LocalThumbPrefetchStore store;
  final LocalThumbPrefetchKeyPredicate isCached;
  final LocalThumbPrefetchKeyPredicate isFailed;
  final LocalThumbPrefetchMarkFailed markFailed;
  final bool debugEnabled;
  final String debugName;
  final int debugLogThrottleMs;

  final PriorityQueue<_QueuedLocalThumbTask> _heap =
      PriorityQueue<_QueuedLocalThumbTask>((a, b) {
        final int byPriority = a.task.priority.compareTo(b.task.priority);
        if (byPriority != 0) {
          return byPriority;
        }
        return a.serial.compareTo(b.serial);
      });
  final Map<String, _QueuedLocalThumbTask> _queuedByKey =
      <String, _QueuedLocalThumbTask>{};
  final Map<String, LocalThumbPrefetchTask> _wantedByKey =
      <String, LocalThumbPrefetchTask>{};
  final Set<String> _inflightKeys = <String>{};

  int _maxConcurrent;
  int _running = 0;
  int _serialSeed = 0;
  bool _disposed = false;
  int _debugUpdateSeq = 0;
  int _lastDebugLogMs = 0;
  int _suppressedDebugLogs = 0;
  String? _lastSuppressedDebugMessage;

  void updateWanted(
    Iterable<LocalThumbPrefetchTask> tasks, {
    int? maxConcurrent,
    int? maxBatchSize,
  }) {
    if (_disposed) {
      return;
    }
    _maxConcurrent = math.max(1, maxConcurrent ?? defaultMaxConcurrent);
    final int resolvedBatchSize = maxBatchSize == null
        ? 1 << 30
        : math.max(1, maxBatchSize);

    final Map<String, LocalThumbPrefetchTask> bestByKey =
        <String, LocalThumbPrefetchTask>{};
    for (final LocalThumbPrefetchTask task in tasks) {
      if (task.cacheKey.isEmpty || task.assetId.isEmpty) {
        continue;
      }
      final LocalThumbPrefetchTask? existing = bestByKey[task.cacheKey];
      if (existing == null ||
          (task.isInViewport && !existing.isInViewport) ||
          (task.isInViewport == existing.isInViewport &&
              task.priority < existing.priority)) {
        bestByKey[task.cacheKey] = task;
      }
    }
    final List<LocalThumbPrefetchTask> prioritized =
        bestByKey.values.toList(growable: false)..sort((a, b) {
          if (a.isInViewport != b.isInViewport) {
            return a.isInViewport ? -1 : 1;
          }
          final int byPriority = a.priority.compareTo(b.priority);
          if (byPriority != 0) {
            return byPriority;
          }
          return a.cacheKey.compareTo(b.cacheKey);
        });
    final int takeCount = math.min(prioritized.length, resolvedBatchSize);
    final Map<String, LocalThumbPrefetchTask> nextWanted =
        <String, LocalThumbPrefetchTask>{};
    for (int i = 0; i < takeCount; i++) {
      final LocalThumbPrefetchTask task = prioritized[i];
      nextWanted[task.cacheKey] = task;
    }

    final int previousWantedCount = _wantedByKey.length;
    final int previousQueuedCount = _queuedByKey.length;
    _wantedByKey
      ..clear()
      ..addAll(nextWanted);

    // Replace queued prefetch snapshot by the newest viewport wanted set.
    _queuedByKey.clear();
    _heap.clear();

    int queuedAdded = 0;
    for (final LocalThumbPrefetchTask task in _wantedByKey.values) {
      final String key = task.cacheKey;
      if (_inflightKeys.contains(key)) {
        continue;
      }
      if (isCached(key) || isFailed(key)) {
        continue;
      }
      final _QueuedLocalThumbTask queued = _QueuedLocalThumbTask(
        serial: ++_serialSeed,
        task: task,
      );
      _queuedByKey[key] = queued;
      _heap.add(queued);
      queuedAdded += 1;
    }

    _logDebug(
      'update#${++_debugUpdateSeq} '
      'wanted=$previousWantedCount->${_wantedByKey.length} '
      'batch=$takeCount '
      'queued=$previousQueuedCount->${_queuedByKey.length} '
      'inflight=${_inflightKeys.length} '
      'added=$queuedAdded',
    );
    _pump();
  }

  void clear() {
    _wantedByKey.clear();
    _queuedByKey.clear();
    _heap.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    while (_running < _maxConcurrent) {
      final _QueuedLocalThumbTask? next = _popNextReadyTask();
      if (next == null) {
        break;
      }
      final LocalThumbPrefetchTask task = next.task;
      final String key = task.cacheKey;

      _inflightKeys.add(key);
      _running += 1;
      _logDebug(
        'request key=${_shortKey(key)} '
        'idx=${task.dataIndex} edge=${task.edge} '
        'viewport=${task.isInViewport} '
        'running=$_running/$_maxConcurrent',
      );
      loader(task)
          .then((Uint8List? bytes) {
            if (_disposed) {
              return;
            }
            final bool stillWanted = _wantedByKey.containsKey(key);
            if (bytes != null && bytes.isNotEmpty) {
              _logDebug(
                'received key=${_shortKey(key)} idx=${task.dataIndex} '
                'bytes=${bytes.lengthInBytes} wanted=$stillWanted',
              );
            }
            if (bytes == null || bytes.isEmpty) {
              if (stillWanted) {
                markFailed(key);
                _logDebug(
                  'fail key=${_shortKey(key)} idx=${task.dataIndex} (still wanted)',
                );
              } else {
                _logDebug(
                  'drop-empty key=${_shortKey(key)} idx=${task.dataIndex} (not wanted)',
                );
              }
              return;
            }
            if (!stillWanted) {
              _logDebug(
                'drop-result key=${_shortKey(key)} idx=${task.dataIndex} (not wanted)',
              );
              return;
            }
            if (isCached(key)) {
              _logDebug(
                'skip-store key=${_shortKey(key)} idx=${task.dataIndex} (already cached)',
              );
              return;
            }
            store(task, bytes);
            _logDebug(
              'store key=${_shortKey(key)} idx=${task.dataIndex} '
              'bytes=${bytes.lengthInBytes}',
            );
          })
          .catchError((Object _) {
            if (_disposed) {
              return;
            }
            if (_wantedByKey.containsKey(key)) {
              markFailed(key);
              _logDebug('error key=${_shortKey(key)} (still wanted)');
            } else {
              _logDebug('error-drop key=${_shortKey(key)} (not wanted)');
            }
          })
          .whenComplete(() {
            _inflightKeys.remove(key);
            _running = _running <= 0 ? 0 : _running - 1;
            _pump();
          });
    }
  }

  _QueuedLocalThumbTask? _popNextReadyTask() {
    while (_heap.isNotEmpty) {
      final _QueuedLocalThumbTask queued = _heap.removeFirst();
      final String key = queued.task.cacheKey;
      final _QueuedLocalThumbTask? currentQueued = _queuedByKey.remove(key);
      if (currentQueued != queued) {
        continue;
      }
      if (!_wantedByKey.containsKey(key)) {
        _logDebug('skip-pop key=${_shortKey(key)} (no longer wanted)');
        continue;
      }
      if (_inflightKeys.contains(key)) {
        continue;
      }
      if (isCached(key) || isFailed(key)) {
        continue;
      }
      return queued;
    }
    return null;
  }

  void _logDebug(String message) {
    if (!debugEnabled) {
      return;
    }
    final int throttleMs = debugLogThrottleMs < 0 ? 0 : debugLogThrottleMs;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (throttleMs > 0 && nowMs - _lastDebugLogMs < throttleMs) {
      _suppressedDebugLogs += 1;
      _lastSuppressedDebugMessage = message;
      return;
    }
    if (_suppressedDebugLogs > 0) {
      debugPrint(
        '[$debugName] (throttled $_suppressedDebugLogs logs) '
        'last=${_lastSuppressedDebugMessage ?? '-'}',
      );
      _suppressedDebugLogs = 0;
      _lastSuppressedDebugMessage = null;
    }
    _lastDebugLogMs = nowMs;
    debugPrint('[$debugName] $message');
  }

  String _shortKey(String key) {
    if (key.length <= 64) {
      return key;
    }
    return '${key.substring(0, 24)}...${key.substring(key.length - 20)}';
  }
}

class _QueuedLocalThumbTask {
  const _QueuedLocalThumbTask({required this.serial, required this.task});

  final int serial;
  final LocalThumbPrefetchTask task;
}
