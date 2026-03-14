import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

enum LocalThumbRequestSource { visible, prefetch }

class LocalThumbRequest {
  const LocalThumbRequest({
    required this.cacheKey,
    required this.dataIndex,
    required this.assetId,
    required this.edge,
    required this.isVideo,
    required this.priority,
    required this.isInViewport,
    required this.source,
  });

  final String cacheKey;
  final int dataIndex;
  final String assetId;
  final int edge;
  final bool isVideo;
  final double priority;
  final bool isInViewport;
  final LocalThumbRequestSource source;
}

class LocalThumbRequestQueue {
  LocalThumbRequestQueue._();

  static final LocalThumbRequestQueue instance = LocalThumbRequestQueue._();

  final PriorityQueue<_QueuedLocalThumbRequest> _heap =
      PriorityQueue<_QueuedLocalThumbRequest>((a, b) {
        final int byPriority = a.priority.compareTo(b.priority);
        if (byPriority != 0) {
          return byPriority;
        }
        return a.serial.compareTo(b.serial);
      });
  final Map<String, _LocalThumbRequestTask> _tasksByKey =
      <String, _LocalThumbRequestTask>{};
  final Set<String> _wantedPrefetchKeys = <String>{};
  final Set<String> _wantedVisibleKeys = <String>{};

  int _maxConcurrent = 4;
  int _running = 0;
  int _serialSeed = 0;
  Uint8List? Function(String cacheKey)? _peekCachedBytes;
  void Function(String cacheKey, Uint8List bytes)? _storeCachedBytes;
  bool _debugEnabled = false;
  String _debugName = 'local_thumb_queue';
  int _debugLogThrottleMs = 120;
  int _lastDebugLogMs = 0;
  int _suppressedDebugLogs = 0;
  String? _lastSuppressedDebugMessage;

  void configure({
    required int maxConcurrent,
    Uint8List? Function(String cacheKey)? peekCachedBytes,
    void Function(String cacheKey, Uint8List bytes)? storeCachedBytes,
    bool? debugEnabled,
    String? debugName,
    int? debugLogThrottleMs,
  }) {
    final int next = maxConcurrent <= 0 ? 1 : maxConcurrent;
    _maxConcurrent = next;
    if (debugEnabled != null) {
      _debugEnabled = debugEnabled;
    }
    if (debugName != null && debugName.trim().isNotEmpty) {
      _debugName = debugName.trim();
    }
    if (debugLogThrottleMs != null) {
      _debugLogThrottleMs = debugLogThrottleMs < 0 ? 0 : debugLogThrottleMs;
    }
    if (peekCachedBytes != null) {
      _peekCachedBytes = peekCachedBytes;
    }
    if (storeCachedBytes != null) {
      _storeCachedBytes = storeCachedBytes;
    }
    _pump();
  }

  void replaceWantedPrefetchKeys(Iterable<String> keys) {
    final Set<String> nextWanted = <String>{};
    for (final String rawKey in keys) {
      final String key = rawKey.trim();
      if (key.isEmpty) {
        continue;
      }
      nextWanted.add(key);
    }
    _wantedPrefetchKeys
      ..clear()
      ..addAll(nextWanted);

    int droppedQueued = 0;
    for (final MapEntry<String, _LocalThumbRequestTask> entry
        in _tasksByKey.entries.toList(growable: false)) {
      final _LocalThumbRequestTask task = entry.value;
      if (task.request.source != LocalThumbRequestSource.prefetch) {
        continue;
      }
      if (task.isStarted) {
        continue;
      }
      if (_wantedPrefetchKeys.contains(entry.key)) {
        continue;
      }
      _tasksByKey.remove(entry.key);
      if (!task.completer.isCompleted) {
        task.completer.complete(null);
      }
      droppedQueued += 1;
    }
    if (droppedQueued > 0) {
      _logDebug(
        'replace-wanted wanted=${_wantedPrefetchKeys.length} droppedQueued=$droppedQueued',
      );
    }
  }

  void replaceWantedVisibleKeys(Iterable<String> keys) {
    final Set<String> nextWanted = <String>{};
    for (final String rawKey in keys) {
      final String key = rawKey.trim();
      if (key.isEmpty) {
        continue;
      }
      nextWanted.add(key);
    }
    _wantedVisibleKeys
      ..clear()
      ..addAll(nextWanted);

    int droppedQueued = 0;
    for (final MapEntry<String, _LocalThumbRequestTask> entry
        in _tasksByKey.entries.toList(growable: false)) {
      final _LocalThumbRequestTask task = entry.value;
      if (task.request.source != LocalThumbRequestSource.visible) {
        continue;
      }
      if (task.isStarted) {
        continue;
      }
      if (_wantedVisibleKeys.contains(entry.key)) {
        continue;
      }
      _tasksByKey.remove(entry.key);
      if (!task.completer.isCompleted) {
        task.completer.complete(null);
      }
      droppedQueued += 1;
    }
    if (droppedQueued > 0) {
      _logDebug(
        'replace-visible wanted=${_wantedVisibleKeys.length} droppedQueued=$droppedQueued',
      );
    }
  }

  Future<Uint8List?> request(LocalThumbRequest request) {
    if (request.cacheKey.isEmpty || request.assetId.isEmpty) {
      return Future<Uint8List?>.value(null);
    }
    final Uint8List? cachedBytes = _peekCachedBytes?.call(request.cacheKey);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      return Future<Uint8List?>.value(cachedBytes);
    }
    if (request.source == LocalThumbRequestSource.prefetch &&
        !_wantedPrefetchKeys.contains(request.cacheKey)) {
      _logDebug(
        'drop-stale-enqueue key=${_shortKey(request.cacheKey)} idx=${request.dataIndex}',
      );
      return Future<Uint8List?>.value(null);
    }
    if (request.source == LocalThumbRequestSource.visible &&
        !_wantedVisibleKeys.contains(request.cacheKey)) {
      _wantedVisibleKeys.add(request.cacheKey);
      _logDebug(
        'append-visible-wanted key=${_shortKey(request.cacheKey)} idx=${request.dataIndex}',
      );
    }
    final _LocalThumbRequestTask? existing = _tasksByKey[request.cacheKey];
    if (existing != null) {
      _logDebug(
        'reuse key=${_shortKey(request.cacheKey)} '
        'idx=${request.dataIndex} src=${request.source.name} '
        'started=${existing.isStarted}',
      );
      _reprioritizeIfNeeded(existing, request);
      return existing.completer.future;
    }
    final _LocalThumbRequestTask task = _LocalThumbRequestTask(
      request: request,
      effectivePriority: _effectivePriority(request),
      serial: ++_serialSeed,
    );
    _tasksByKey[request.cacheKey] = task;
    _heap.add(
      _QueuedLocalThumbRequest(
        cacheKey: task.request.cacheKey,
        version: task.version,
        priority: task.effectivePriority,
        serial: task.serial,
      ),
    );
    _logDebug(
      'enqueue key=${_shortKey(request.cacheKey)} '
      'idx=${request.dataIndex} src=${request.source.name} '
      'viewport=${request.isInViewport} p=${task.effectivePriority.toStringAsFixed(2)}',
    );
    _pump();
    return task.completer.future;
  }

  void enqueue(LocalThumbRequest request) {
    unawaited(this.request(request));
  }

  void _reprioritizeIfNeeded(
    _LocalThumbRequestTask task,
    LocalThumbRequest nextRequest,
  ) {
    if (task.isStarted) {
      return;
    }
    final double nextPriority = _effectivePriority(nextRequest);
    final bool shouldUpgrade = nextPriority < task.effectivePriority;
    if (!shouldUpgrade) {
      return;
    }
    task.request = nextRequest;
    task.effectivePriority = nextPriority;
    task.version += 1;
    task.serial = ++_serialSeed;
    _heap.add(
      _QueuedLocalThumbRequest(
        cacheKey: task.request.cacheKey,
        version: task.version,
        priority: task.effectivePriority,
        serial: task.serial,
      ),
    );
    _logDebug(
      'reprioritize key=${_shortKey(task.request.cacheKey)} '
      'idx=${task.request.dataIndex} src=${task.request.source.name} '
      'p=${task.effectivePriority.toStringAsFixed(2)}',
    );
  }

  void _pump() {
    while (_running < _maxConcurrent) {
      final _LocalThumbRequestTask? task = _popNextTask();
      if (task == null) {
        break;
      }
      _running += 1;
      task.isStarted = true;
      final LocalThumbRequest request = task.request;
      _logDebug(
        'start key=${_shortKey(request.cacheKey)} idx=${request.dataIndex} '
        'src=${request.source.name} running=$_running/$_maxConcurrent',
      );
      unawaited(
        _decodeThumbBytes(request)
            .then((Uint8List? bytes) {
              if (bytes != null && bytes.isNotEmpty) {
                final Uint8List? existing = _peekCachedBytes?.call(
                  request.cacheKey,
                );
                if (existing == null || existing.isEmpty) {
                  _storeCachedBytes?.call(request.cacheKey, bytes);
                }
              }
              if (!task.completer.isCompleted) {
                task.completer.complete(bytes);
              }
            })
            .catchError((Object error, StackTrace stackTrace) {
              if (!task.completer.isCompleted) {
                task.completer.complete(null);
              }
            })
            .whenComplete(() {
              _tasksByKey.remove(request.cacheKey);
              _running = _running <= 0 ? 0 : _running - 1;
              _pump();
            }),
      );
    }
  }

  _LocalThumbRequestTask? _popNextTask() {
    while (_heap.isNotEmpty) {
      final _QueuedLocalThumbRequest queued = _heap.removeFirst();
      final _LocalThumbRequestTask? task = _tasksByKey[queued.cacheKey];
      if (task == null) {
        continue;
      }
      if (task.isStarted) {
        continue;
      }
      if (queued.version != task.version) {
        continue;
      }
      if (task.request.source == LocalThumbRequestSource.prefetch &&
          !_wantedPrefetchKeys.contains(task.request.cacheKey)) {
        _tasksByKey.remove(task.request.cacheKey);
        if (!task.completer.isCompleted) {
          task.completer.complete(null);
        }
        _logDebug(
          'drop-stale-pop key=${_shortKey(task.request.cacheKey)} idx=${task.request.dataIndex}',
        );
        continue;
      }
      if (task.request.source == LocalThumbRequestSource.visible &&
          _wantedVisibleKeys.isNotEmpty &&
          !_wantedVisibleKeys.contains(task.request.cacheKey)) {
        _tasksByKey.remove(task.request.cacheKey);
        if (!task.completer.isCompleted) {
          task.completer.complete(null);
        }
        _logDebug(
          'drop-stale-visible-pop key=${_shortKey(task.request.cacheKey)} '
          'idx=${task.request.dataIndex}',
        );
        continue;
      }
      return task;
    }
    return null;
  }

  double _effectivePriority(LocalThumbRequest request) {
    final double sourceBias = switch (request.source) {
      LocalThumbRequestSource.visible => -10000,
      LocalThumbRequestSource.prefetch => request.isInViewport ? 0 : 1000,
    };
    return sourceBias + request.priority;
  }

  Future<Uint8List?> _decodeThumbBytes(LocalThumbRequest request) async {
    try {
      final AssetEntity? asset = await AssetEntity.fromId(request.assetId);
      if (asset == null) {
        return null;
      }
      final AssetType expectedType = request.isVideo
          ? AssetType.video
          : AssetType.image;
      if (asset.type != expectedType) {
        return null;
      }
      final int safeEdge = request.edge <= 0 ? 300 : request.edge;
      final int quality = request.isVideo
          ? (safeEdge <= 64 ? 56 : 78)
          : (safeEdge <= 64 ? 62 : 84);
      final Uint8List? bytes = await asset.thumbnailDataWithSize(
        ThumbnailSize.square(safeEdge),
        quality: quality,
      );
      if (bytes != null && bytes.isNotEmpty) {
        _logDebug(
          'received key=${_shortKey(request.cacheKey)} '
          'idx=${request.dataIndex} bytes=${bytes.lengthInBytes}',
        );
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _logDebug(String message) {
    if (!_debugEnabled) {
      return;
    }
    final int throttleMs = _debugLogThrottleMs;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (throttleMs > 0 && nowMs - _lastDebugLogMs < throttleMs) {
      _suppressedDebugLogs += 1;
      _lastSuppressedDebugMessage = message;
      return;
    }
    if (_suppressedDebugLogs > 0) {
      debugPrint(
        '[$_debugName] (throttled $_suppressedDebugLogs logs) '
        'last=${_lastSuppressedDebugMessage ?? '-'}',
      );
      _suppressedDebugLogs = 0;
      _lastSuppressedDebugMessage = null;
    }
    _lastDebugLogMs = nowMs;
    debugPrint('[$_debugName] $message');
  }

  String _shortKey(String key) {
    if (key.length <= 64) {
      return key;
    }
    return '${key.substring(0, 24)}...${key.substring(math.max(24, key.length - 20))}';
  }
}

class _QueuedLocalThumbRequest {
  const _QueuedLocalThumbRequest({
    required this.cacheKey,
    required this.version,
    required this.priority,
    required this.serial,
  });

  final String cacheKey;
  final int version;
  final double priority;
  final int serial;
}

class _LocalThumbRequestTask {
  _LocalThumbRequestTask({
    required this.request,
    required this.effectivePriority,
    required this.serial,
  });

  LocalThumbRequest request;
  double effectivePriority;
  int serial;
  int version = 0;
  bool isStarted = false;
  final Completer<Uint8List?> completer = Completer<Uint8List?>();
}
