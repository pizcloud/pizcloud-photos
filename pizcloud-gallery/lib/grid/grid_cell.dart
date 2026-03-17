import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import './cell_data.dart';
import './grid_appearance_config.dart';
import './grid_thumbnail_cache_manager.dart';
import './local_thumb_request_queue.dart';
import './lru_bytes_cache.dart';
import './media_hero_flight.dart';
import './media_hero_tag.dart';
import './media_item.dart';
import './storage_indicator.dart'; // new
import 'sources/local_device_media_uri.dart';

part 'cell/grid_cell_models.dart';
part 'cell/grid_cell_render.dart';
part 'cell/grid_cell_resolver.dart';

class GridCell extends StatefulWidget {
  final CellData data;
  final double size;
  final LruBytesCache bytesCache;
  final VoidCallback? onTap;
  static const double _cellGap = 1.0;
  static const bool _showIndexBadge = false;

  const GridCell({
    super.key,
    required this.data,
    required this.size,
    required this.bytesCache,
    this.onTap,
  });

  @override
  State<GridCell> createState() => _GridCellState();
}

class _GridCellState extends State<GridCell> {
  static const int _maxRememberedProviders = 1200;
  static const int _maxRememberedLocalAssetFileFutures = 700;
  static const int _maxRememberedLocalThumbFailures = 1200;
  static const Duration _localEmergencyEnqueueDelay = Duration(
    milliseconds: 180,
  );
  static const bool _enableLocalCacheLogs = false;
  static const int _localCacheLogEveryLookups = 200;
  static const int _localCacheLogMinIntervalMs = 1200;
  static const int _maxRememberedLookupKeys = 12000;

  static final LinkedHashMap<String, _ShownThumb> _shownByMediaId =
      LinkedHashMap<String, _ShownThumb>();
  static final LinkedHashMap<String, Future<File?>> _localAssetFileFutureById =
      LinkedHashMap<String, Future<File?>>();
  static final LinkedHashMap<String, bool> _failedLocalThumbByKey =
      LinkedHashMap<String, bool>();
  static int _localRenderCacheHits = 0;
  static int _localRenderCacheMisses = 0;
  static int _localResolverCacheHits = 0;
  static int _localResolverCacheMisses = 0;
  static int _localResolverNoKey = 0;
  static int _lastLocalCacheLogMs = 0;
  static int _lastLoggedRenderHits = 0;
  static int _lastLoggedRenderMisses = 0;
  static int _lastLoggedResolverHits = 0;
  static int _lastLoggedResolverMisses = 0;
  static int _lastLoggedResolverNoKey = 0;
  static final LinkedHashSet<String> _renderLookupKeys =
      LinkedHashSet<String>();
  static final LinkedHashSet<String> _resolverLookupKeys =
      LinkedHashSet<String>();

  _ThumbRequest? _shownRequest;
  ImageProvider<Object>? _shownProvider;

  _ThumbRequest? _pendingRequest;
  ImageStream? _pendingStream;
  ImageStreamListener? _pendingListener;

  int _localResolveToken = 0;
  int _requestToken = 0;
  Timer? _localEmergencyEnqueueTimer;
  String? _localEmergencyEnqueueKey;

  Uint8List? _lastShownLocalFrameBytes;
  String? _lastShownLocalFrameKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncProvider(force: true);
  }

  @override
  void didUpdateWidget(covariant GridCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size ||
        !oldWidget.data.sameVisual(widget.data) ||
        oldWidget.data.mediaItem?.id != widget.data.mediaItem?.id) {
      _syncProvider();
    }
  }

  @override
  void dispose() {
    _cancelPendingLocalResolve();
    _cancelPendingResolve();
    _localEmergencyEnqueueTimer?.cancel();
    _localEmergencyEnqueueTimer = null;
    super.dispose();
  }

  void _setState(VoidCallback fn) {
    setState(fn);
  }

  void _reportLocalCacheLookup({
    required bool hit,
    required bool fromRenderStage,
    bool noKey = false,
    String? key,
  }) {
    if (!_enableLocalCacheLogs) {
      return;
    }
    if (fromRenderStage) {
      _rememberLookupKey(_renderLookupKeys, key);
      if (hit) {
        _localRenderCacheHits += 1;
      } else {
        _localRenderCacheMisses += 1;
      }
    } else if (noKey) {
      _localResolverNoKey += 1;
    } else if (hit) {
      _rememberLookupKey(_resolverLookupKeys, key);
      _localResolverCacheHits += 1;
    } else {
      _rememberLookupKey(_resolverLookupKeys, key);
      _localResolverCacheMisses += 1;
    }

    final int totalLookups =
        _localRenderCacheHits +
        _localRenderCacheMisses +
        _localResolverCacheHits +
        _localResolverCacheMisses +
        _localResolverNoKey;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final bool enoughCount = totalLookups % _localCacheLogEveryLookups == 0;
    final bool enoughTime =
        nowMs - _lastLocalCacheLogMs >= _localCacheLogMinIntervalMs;
    if (!enoughCount && !enoughTime) {
      return;
    }
    _lastLocalCacheLogMs = nowMs;

    final int renderTotal = _localRenderCacheHits + _localRenderCacheMisses;
    final int resolverTotal =
        _localResolverCacheHits + _localResolverCacheMisses;
    final double renderHitRate = renderTotal == 0
        ? 0
        : (_localRenderCacheHits / renderTotal) * 100;
    final double resolverHitRate = resolverTotal == 0
        ? 0
        : (_localResolverCacheHits / resolverTotal) * 100;
    final int deltaRenderHits = _localRenderCacheHits - _lastLoggedRenderHits;
    final int deltaRenderMisses =
        _localRenderCacheMisses - _lastLoggedRenderMisses;
    final int deltaResolverHits =
        _localResolverCacheHits - _lastLoggedResolverHits;
    final int deltaResolverMisses =
        _localResolverCacheMisses - _lastLoggedResolverMisses;
    final int deltaResolverNoKey =
        _localResolverNoKey - _lastLoggedResolverNoKey;

    _lastLoggedRenderHits = _localRenderCacheHits;
    _lastLoggedRenderMisses = _localRenderCacheMisses;
    _lastLoggedResolverHits = _localResolverCacheHits;
    _lastLoggedResolverMisses = _localResolverCacheMisses;
    _lastLoggedResolverNoKey = _localResolverNoKey;

    debugPrint(
      '📊 LocalThumbCache '
      'render hit/miss=$_localRenderCacheHits/$_localRenderCacheMisses '
      '(${renderHitRate.toStringAsFixed(1)}%) | '
      'resolver hit/miss=$_localResolverCacheHits/$_localResolverCacheMisses '
      '(${resolverHitRate.toStringAsFixed(1)}%) | '
      'resolver noKey=$_localResolverNoKey | '
      'unique render/resolver=${_renderLookupKeys.length}/${_resolverLookupKeys.length} | '
      'delta render hit/miss=$deltaRenderHits/$deltaRenderMisses, '
      'resolver hit/miss=$deltaResolverHits/$deltaResolverMisses, '
      'noKey=$deltaResolverNoKey',
    );
  }

  static void _rememberLookupKey(LinkedHashSet<String> bucket, String? key) {
    final String normalized = key?.trim() ?? '';
    if (normalized.isEmpty) {
      return;
    }
    if (bucket.contains(normalized)) {
      return;
    }
    bucket.add(normalized);
    while (bucket.length > _maxRememberedLookupKeys) {
      bucket.remove(bucket.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MediaItem? media = widget.data.mediaItem;
    final GridAppearancePalette palette = GridAppearancePalette.of(context);

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Padding(
            padding: const EdgeInsets.all(GridCell._cellGap / 2),
            child: DecoratedBox(
              decoration: BoxDecoration(color: palette.cellBackground),
              child: media == null
                  ? _buildFallback(palette)
                  : Hero(
                      tag: mediaGridCellHeroTag(
                        mediaId: media.id,
                        cellId: widget.data.id,
                      ),
                      transitionOnUserGestures: true,
                      createRectTween: mediaHeroRectTween,
                      flightShuttleBuilder: mediaHeroFlightShuttleBuilder,
                      child: _buildListenableMedia(media, palette),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
