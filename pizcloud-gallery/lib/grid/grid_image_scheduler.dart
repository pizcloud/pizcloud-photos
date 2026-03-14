import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'grid_window.dart';

typedef GridImageProviderBuilder = ImageProvider<Object> Function(String url);
typedef GridWindowUrlCollector = Iterable<String> Function(GridWindow window);

class GridImageScheduler {
  final Duration debounceDuration;
  final int maxConcurrent;
  final int maxQueueLength;
  final int maxRememberedUrls;
  final bool Function() isAlive;
  final bool Function() isEnabled;
  final GridImageProviderBuilder providerBuilder;

  Timer? _debounce;
  GridWindow? _lastWindow;
  final Set<String> _warmingUrls = <String>{};
  final Set<String> _warmedUrls = <String>{};
  final Queue<String> _warmQueue = Queue<String>();
  int _warmingInFlight = 0;
  bool _disposed = false;

  GridImageScheduler({
    required this.isAlive,
    required this.isEnabled,
    required this.providerBuilder,
    this.debounceDuration = const Duration(milliseconds: 220),
    this.maxConcurrent = 2,
    this.maxQueueLength = 160,
    this.maxRememberedUrls = 4000,
  });

  void schedule({
    required GridWindow window,
    required ImageConfiguration imageConfiguration,
    required GridWindowUrlCollector collectUrls,
  }) {
    if (_disposed || !isAlive() || !isEnabled()) return;
    if (_sameWindow(_lastWindow, window)) return;
    _warmQueue.clear();
    _lastWindow = window;
    if (_debounce?.isActive ?? false) return;
    _debounce = Timer(debounceDuration, () {
      _debounce = null;
      if (_disposed || !isAlive() || !isEnabled()) return;
      final GridWindow? targetWindow = _lastWindow;
      if (targetWindow == null) return;
      final Iterable<String> urls = collectUrls(targetWindow);
      for (final String url in urls) {
        _enqueueWarmUrl(url);
      }
      _drainWarmQueue(imageConfiguration);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    _lastWindow = null;
    _warmingUrls.clear();
    _warmedUrls.clear();
    _warmQueue.clear();
    _warmingInFlight = 0;
  }

  bool _sameWindow(GridWindow? a, GridWindow b) {
    if (a == null) return false;
    return a.firstRow == b.firstRow &&
        a.lastRow == b.lastRow &&
        a.firstCol == b.firstCol &&
        a.lastCol == b.lastCol;
  }

  void _enqueueWarmUrl(String url) {
    if (_disposed || !isEnabled()) return;
    if (_warmedUrls.contains(url) || _warmingUrls.contains(url)) return;
    if (_warmQueue.contains(url)) return;
    _warmQueue.addLast(url);
    while (_warmQueue.length > maxQueueLength) {
      _warmQueue.removeFirst();
    }
  }

  void _drainWarmQueue(ImageConfiguration imageConfiguration) {
    if (_disposed || !isAlive() || !isEnabled()) return;
    while (_warmingInFlight < maxConcurrent && _warmQueue.isNotEmpty) {
      final String nextUrl = _warmQueue.removeFirst();
      _warmUrl(nextUrl, imageConfiguration);
    }
  }

  void _warmUrl(String url, ImageConfiguration imageConfiguration) {
    if (_disposed || !isAlive() || !isEnabled()) return;
    _warmingUrls.add(url);
    _warmingInFlight += 1;
    final ImageProvider<Object> provider = providerBuilder(url);
    unawaited(
      _resolveFirstFrame(provider, imageConfiguration)
          .then((_) {
            _warmedUrls.add(url);
            while (_warmedUrls.length > maxRememberedUrls) {
              _warmedUrls.remove(_warmedUrls.first);
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            _warmingUrls.remove(url);
            _warmingInFlight = _warmingInFlight <= 0 ? 0 : _warmingInFlight - 1;
            _drainWarmQueue(imageConfiguration);
          }),
    );
  }

  Future<void> _resolveFirstFrame(
    ImageProvider<Object> provider,
    ImageConfiguration imageConfiguration,
  ) {
    final Completer<void> completer = Completer<void>();
    final ImageStream stream = provider.resolve(imageConfiguration);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, syncCall) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}
