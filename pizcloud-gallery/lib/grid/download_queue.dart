import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:pizcloud_gallery/grid/dio_bytes_loader.dart';
import 'package:pizcloud_gallery/grid/download_queue_item.dart';
import 'package:pizcloud_gallery/grid/lru_bytes_cache.dart';
import 'package:pizcloud_gallery/grid/queue_strategy.dart';

class DownloadQueue {
  DownloadQueue({
    required this.maxConcurrent,
    required this.cache,
    this.strategy = QueueStrategy.priority2d,
    this.enableCompact = true,
    this.compactFactor = 3,
    DioBytesLoader? loader,
  }) : loader = loader ?? DioBytesLoader();

  final int maxConcurrent;
  final LruBytesCache cache;
  final QueueStrategy strategy;
  final bool enableCompact;
  final int compactFactor;
  final DioBytesLoader loader;

  final Set<String> _wanted = <String>{};
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  final Set<String> _inflight = <String>{};

  final PriorityQueue<DownloadQueueItem> _heap = PriorityQueue<DownloadQueueItem>(
    (DownloadQueueItem a, DownloadQueueItem b) => a.priority.compareTo(b.priority),
  );
  final Queue<DownloadQueueItem> _deque = Queue<DownloadQueueItem>();
  final Map<String, DownloadQueueItem> _queuedMap = <String, DownloadQueueItem>{};

  int running = 0;

  final ValueNotifier<int> statsTick = ValueNotifier<int>(0);

  int get pendingLength => _queuedMap.length;
  int get wantedLength => _wanted.length;

  bool isInflight(String key) => _inflight.contains(key);

  void setWanted(Set<String> wantedUrls) {
    _wanted
      ..clear()
      ..addAll(wantedUrls);

    for (final String url in _inflight.toList()) {
      if (!_wanted.contains(url)) {
        _cancelInflight(url);
      }
    }

    if (enableCompact) {
      _maybeCompact();
    }
    _pump();
    _tick();
  }

  void ensure(String url, double priority) {
    ensureMany(<String, double>{url: priority});
  }

  void ensureMany(Map<String, double> urlToPriority) {
    var changed = false;

    for (final MapEntry<String, double> entry in urlToPriority.entries) {
      final String url = entry.key;
      final double priority = entry.value;

      if (!_wanted.contains(url)) continue;
      if (cache.contains(url)) continue;
      if (_inflight.contains(url)) continue;

      final DownloadQueueItem? existing = _queuedMap[url];
      if (existing != null) {
        if (strategy == QueueStrategy.priority2d &&
            priority < existing.priority) {
          _removePending(existing);
          _addPending(DownloadQueueItem(url, priority));
          changed = true;
        }
        continue;
      }

      _addPending(DownloadQueueItem(url, priority));
      changed = true;
    }

    if (!changed) return;
    _pump();
    _tick();
  }

  void cancel(String url) {
    _wanted.remove(url);
    _cancelInflight(url);

    final DownloadQueueItem? existing = _queuedMap[url];
    if (existing != null) {
      _removePending(existing);
    }
    _tick();
  }

  void disposeAll() {
    _wanted.clear();
    for (final t in _tokens.values) {
      t.cancel('dispose');
    }
    _tokens.clear();
    _inflight.clear();

    _heap.clear();
    _deque.clear();
    _queuedMap.clear();

    _tick();
  }

  void _cancelInflight(String url) {
    _tokens.remove(url)?.cancel('off-viewport');
    _inflight.remove(url);
  }

  void _addPending(DownloadQueueItem item) {
    _queuedMap[item.url] = item;
    switch (strategy) {
      case QueueStrategy.priority2d:
        _heap.add(item);
        break;
      case QueueStrategy.lifo:
      case QueueStrategy.fifo:
        _deque.addLast(item);
        break;
    }
  }

  void _removePending(DownloadQueueItem item) {
    _queuedMap.remove(item.url);
    switch (strategy) {
      case QueueStrategy.priority2d:
        _heap.remove(item);
        break;
      case QueueStrategy.lifo:
      case QueueStrategy.fifo:
        _deque.remove(item);
        break;
    }
  }

  DownloadQueueItem? _popNextPending() {
    switch (strategy) {
      case QueueStrategy.priority2d:
        if (_heap.isEmpty) return null;
        return _heap.removeFirst();
      case QueueStrategy.lifo:
        if (_deque.isEmpty) return null;
        return _deque.removeLast();
      case QueueStrategy.fifo:
        if (_deque.isEmpty) return null;
        return _deque.removeFirst();
    }
  }

  void _pump() {
    while (running < maxConcurrent) {
      final DownloadQueueItem? item = _popNextPending();
      if (item == null) {
        break;
      }
      final String url = item.url;
      _queuedMap.remove(url);

      if (!_wanted.contains(url)) {
        continue;
      }
      if (cache.contains(url)) {
        continue;
      }

      final CancelToken token = CancelToken();
      _tokens[url] = token;
      _inflight.add(url);

      running++;
      loader
          .load(url, token)
          .then((bytes) {
        if (!_wanted.contains(url)) return;
        cache.put(url, bytes);
      }).catchError((e) {
        // ignore
      }).whenComplete(() {
        running = running <= 0 ? 0 : running - 1;
        _tokens.remove(url);
        _inflight.remove(url);
        _pump();
        _tick();
      });
    }
  }

  void _maybeCompact() {
    final int pendingCount = strategy == QueueStrategy.priority2d
        ? _heap.length
        : _deque.length;
    if (pendingCount <= _wanted.length * compactFactor) {
      return;
    }

    final Map<String, DownloadQueueItem> nextQueued = <String, DownloadQueueItem>{};

    if (strategy == QueueStrategy.priority2d) {
      final PriorityQueue<DownloadQueueItem> fresh = PriorityQueue<DownloadQueueItem>(
        (DownloadQueueItem a, DownloadQueueItem b) => a.priority.compareTo(b.priority),
      );
      for (final DownloadQueueItem item in _queuedMap.values) {
        if (_wanted.contains(item.url)) {
          fresh.add(item);
          nextQueued[item.url] = item;
        }
      }
      _heap.clear();
      while (fresh.isNotEmpty) {
        _heap.add(fresh.removeFirst());
      }
    } else {
      final Queue<DownloadQueueItem> fresh = Queue<DownloadQueueItem>();
      for (final DownloadQueueItem item in _deque) {
        if (_wanted.contains(item.url) && _queuedMap.containsKey(item.url)) {
          fresh.addLast(item);
          nextQueued[item.url] = item;
        }
      }
      _deque
        ..clear()
        ..addAll(fresh);
    }

    _queuedMap
      ..clear()
      ..addAll(nextQueued);
  }

  void _tick() => statsTick.value++;
}
