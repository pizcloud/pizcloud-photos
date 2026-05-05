import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';

import 'viewer_cache_manager.dart';
import 'viewer_local_preview_cache.dart';

class ViewerPrefetcher {
  static const int _maxLocalPreviewItems = 2;

  ViewerPrefetcher({this.maxItems = 5});

  final int maxItems;

  final Queue<String> _queue = Queue<String>();
  final Set<String> _queuedSet = <String>{};
  final Map<String, int> _queuedIndexHints = <String, int>{};
  final Map<String, int?> _queuedWidths = <String, int?>{};
  final Map<String, int?> _queuedHeights = <String, int?>{};
  bool _isDraining = false;
  final Queue<_LocalPreviewTarget> _localQueue = Queue<_LocalPreviewTarget>();
  final Set<String> _localQueuedSources = <String>{};
  bool _isLocalDraining = false;

  void prefetchAround({
    required BuildContext context,
    required List<MediaItem> items,
    required int centerIndex,
  }) {
    if (items.isEmpty) return;
    if (maxItems > 0) {
      final int decodeWidth = ViewerCacheManager.decodeWidthForContext(context);
      final List<_PrefetchTarget> targets = _collectTargetUrls(
        items: items,
        centerIndex: centerIndex,
        limit: maxItems,
      );
      _prioritizeTargets(targets);
      if (_queue.isNotEmpty) {
        _drainQueue(context, decodeWidth);
      }
    }

    final List<_LocalPreviewTarget> localTargets = _collectLocalPreviewTargets(
      items: items,
      centerIndex: centerIndex,
      limit: _maxLocalPreviewItems,
    );
    _prioritizeLocalTargets(localTargets);
    if (_localQueue.isNotEmpty) {
      _drainLocalQueue(context);
    }
  }

  void _prioritizeTargets(List<_PrefetchTarget> targets) {
    if (targets.isEmpty) return;

    // Add/move wanted URLs to the front while preserving target priority:
    // index+1, index-1, index+2, index-2, ...
    for (int i = targets.length - 1; i >= 0; i--) {
      final _PrefetchTarget target = targets[i];
      final String url = target.url;
      final bool removed = _queue.remove(url);
      final bool alreadyQueued = removed || _queuedSet.contains(url);
      if (!alreadyQueued) {
        _queuedSet.add(url);
      }
      _queuedIndexHints[url] = target.index;
      _queuedWidths[url] = target.width;
      _queuedHeights[url] = target.height;
      if (removed || !alreadyQueued) {
        _queue.addFirst(url);
      }
    }
  }

  List<_PrefetchTarget> _collectTargetUrls({
    required List<MediaItem> items,
    required int centerIndex,
    required int limit,
  }) {
    final List<_PrefetchTarget> urls = <_PrefetchTarget>[];
    int delta = 1;
    while (urls.length < limit) {
      var added = false;
      final int next = centerIndex + delta;
      if (next < items.length) {
        final String? url = _networkImageUrl(items[next]);
        if (url != null) {
          urls.add(
            _PrefetchTarget(
              url: url,
              index: next,
              width: items[next].width,
              height: items[next].height,
            ),
          );
          added = true;
        }
      }
      if (urls.length >= limit) break;
      final int prev = centerIndex - delta;
      if (prev >= 0) {
        final String? url = _networkImageUrl(items[prev]);
        if (url != null) {
          urls.add(
            _PrefetchTarget(
              url: url,
              index: prev,
              width: items[prev].width,
              height: items[prev].height,
            ),
          );
          added = true;
        }
      }
      if (!added) break;
      delta++;
    }
    return urls;
  }

  void _prioritizeLocalTargets(List<_LocalPreviewTarget> targets) {
    if (targets.isEmpty) return;

    // Keep highest-priority local preview sources at the front.
    for (int i = targets.length - 1; i >= 0; i--) {
      final _LocalPreviewTarget target = targets[i];
      final bool removed = _removeLocalTargetBySource(target.source);
      final bool alreadyQueued =
          removed || _localQueuedSources.contains(target.source);
      if (!alreadyQueued) {
        _localQueuedSources.add(target.source);
      }
      if (removed || !alreadyQueued) {
        _localQueue.addFirst(target);
      }
    }
  }

  bool _removeLocalTargetBySource(String source) {
    final int before = _localQueue.length;
    _localQueue.removeWhere((target) => target.source == source);
    return _localQueue.length != before;
  }

  List<_LocalPreviewTarget> _collectLocalPreviewTargets({
    required List<MediaItem> items,
    required int centerIndex,
    required int limit,
  }) {
    if (limit <= 0) {
      return const <_LocalPreviewTarget>[];
    }
    final List<_LocalPreviewTarget> targets = <_LocalPreviewTarget>[];
    final Set<String> seenSources = <String>{};

    bool addIndex(int index) {
      if (index < 0 || index >= items.length) {
        return false;
      }
      final MediaItem item = items[index];
      if (!item.isLocal) {
        return false;
      }
      final String? source = ViewerLocalPreviewCache.pickPreviewSource(item);
      if (source == null || source.isEmpty) {
        return false;
      }
      if (!seenSources.add(source)) {
        return false;
      }
      if (ViewerLocalPreviewCache.peek(source) != null) {
        return false;
      }
      targets.add(_LocalPreviewTarget(source: source, index: index));
      return true;
    }

    addIndex(centerIndex);
    int delta = 1;
    while (targets.length < limit) {
      bool added = false;
      if (addIndex(centerIndex + delta)) {
        added = true;
      }
      if (targets.length >= limit) {
        break;
      }
      if (addIndex(centerIndex - delta)) {
        added = true;
      }
      if (!added) {
        break;
      }
      delta++;
    }

    return targets;
  }

  void _drainQueue(BuildContext context, int decodeWidth) {
    if (_isDraining) return;
    _isDraining = true;
    () async {
      try {
        while (_queue.isNotEmpty) {
          if (!context.mounted) break;
          final String url = _queue.removeFirst();
          _queuedSet.remove(url);
          final int? indexHint = _queuedIndexHints.remove(url);
          final int? originalWidth = _queuedWidths.remove(url);
          final int? originalHeight = _queuedHeights.remove(url);
          await _prefetchOne(
            context,
            url,
            decodeWidth,
            indexHint: indexHint,
            originalWidth: originalWidth,
            originalHeight: originalHeight,
          );
        }
      } finally {
        _isDraining = false;
        if (_queue.isNotEmpty && context.mounted) {
          _drainQueue(context, decodeWidth);
        }
      }
    }();
  }

  void _drainLocalQueue(BuildContext context) {
    if (_isLocalDraining) return;
    _isLocalDraining = true;
    () async {
      try {
        while (_localQueue.isNotEmpty) {
          if (!context.mounted) break;
          final _LocalPreviewTarget target = _localQueue.removeFirst();
          _localQueuedSources.remove(target.source);
          if (ViewerLocalPreviewCache.peek(target.source) != null) {
            continue;
          }
          final bytes = await ViewerLocalPreviewCache.resolve(target.source);
          if (bytes == null || bytes.isEmpty) {
            continue;
          }
          ViewerLocalPreviewCache.put(target.source, bytes);
        }
      } finally {
        _isLocalDraining = false;
        if (_localQueue.isNotEmpty && context.mounted) {
          _drainLocalQueue(context);
        }
      }
    }();
  }

  Future<void> _prefetchOne(
    BuildContext context,
    String url,
    int decodeWidth, {
    int? indexHint,
    int? originalWidth,
    int? originalHeight,
  }) async {
    if (!context.mounted) return;
    // no explicit video playback guard here
    if (_isVideoPlaybackUrl(url)) {
      return;
    } // new
    final ViewerCacheManager cache = ViewerCacheManager.instance;
    if (indexHint != null) {
      ViewerCacheManager.registerDebugIndex(url, indexHint);
    }
    final int resolvedDecodeWidth = _resolveDecodeWidth(
      decodeWidth: decodeWidth,
      originalWidth: originalWidth,
    );
    final int? decodeHeight = _decodeHeightForWidth(
      decodeWidth: resolvedDecodeWidth,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
    );
    final bool inDiskCache = await cache.isCachedOnDisk(
      url,
      maxWidth: resolvedDecodeWidth,
      maxHeight: decodeHeight,
    );
    if (!inDiskCache) {
      try {
        await cache.getSingleFile(url);
      } catch (_) {
        return;
      }
    }

    if (!context.mounted) return;
    try {
      await precacheImage(
        ViewerCacheManager.providerFor(
          url,
          maxWidth: resolvedDecodeWidth,
          maxHeight: decodeHeight,
          debugIndex: indexHint,
        ),
        context,
      );
    } catch (_) {
      // ignore prefetch errors
    }
  }

  String? _networkImageUrl(MediaItem item) {
    // final String url = item.originalUrl;
    // if (url.startsWith('http://') || url.startsWith('https://')) {
    //   return url;
    // }
    // return null;
    if (item.isVideo) {
      return null;
    } // new
    final String url = item.originalUrl;
    if (_isVideoPlaybackUrl(url)) {
      return null;
    } // new
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return null;
  }

  // new
  bool _isVideoPlaybackUrl(String url) {
    if (url.isEmpty) {
      return false;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    return uri.path.contains('/video/playback');
  }
  // #new

  int _resolveDecodeWidth({required int decodeWidth, int? originalWidth}) {
    if (originalWidth == null || originalWidth <= 0) {
      return decodeWidth;
    }
    return decodeWidth.clamp(1, originalWidth).toInt();
  }

  int? _decodeHeightForWidth({
    required int decodeWidth,
    int? originalWidth,
    int? originalHeight,
  }) {
    if (originalWidth == null ||
        originalHeight == null ||
        originalWidth <= 0 ||
        originalHeight <= 0 ||
        decodeWidth <= 0) {
      return null;
    }
    return (decodeWidth * originalHeight / originalWidth)
        .round()
        .clamp(1, originalHeight)
        .toInt();
  }
}

class _PrefetchTarget {
  const _PrefetchTarget({
    required this.url,
    required this.index,
    this.width,
    this.height,
  });

  final String url;
  final int index;
  final int? width;
  final int? height;
}

class _LocalPreviewTarget {
  const _LocalPreviewTarget({required this.source, required this.index});

  final String source;
  final int index;
}
