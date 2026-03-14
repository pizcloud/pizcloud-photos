import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:pizcloud_gallery/grid/download_queue.dart';
import 'package:pizcloud_gallery/grid/fps_overlay.dart';
import 'package:pizcloud_gallery/grid/grid_date_overlay.dart'; // new
import 'package:pizcloud_gallery/grid/gallery_sort_filter_menu.dart';
import 'package:pizcloud_gallery/grid/grid_gesture_controller.dart';
import 'package:pizcloud_gallery/grid/grid_cell_pool.dart';
import 'package:pizcloud_gallery/grid/grid_prefetch_controller.dart';
import 'package:pizcloud_gallery/grid/grid_appearance_config.dart';
import 'package:pizcloud_gallery/grid/grid_visible_cells_builder.dart';
import 'package:pizcloud_gallery/grid/grid_window.dart';
import 'package:pizcloud_gallery/grid/local_thumb_prefetch_scheduler.dart';
import 'package:pizcloud_gallery/grid/local_thumb_request_queue.dart';
import 'package:pizcloud_gallery/grid/media_data_source.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';
import 'package:pizcloud_gallery/grid/piz_gallery_source.dart';
import 'package:pizcloud_gallery/grid/grid_state.dart';
import 'package:pizcloud_gallery/grid/grid_state_helper.dart';
import 'package:pizcloud_gallery/grid/lru_bytes_cache.dart';
import 'package:pizcloud_gallery/grid/queue_strategy.dart';
import 'package:pizcloud_gallery/grid/real_data_scrollbar.dart';
import 'package:pizcloud_gallery/grid/snap_scroll_physics.dart';
import 'package:pizcloud_gallery/grid/trailing_throttler.dart';
import 'package:pizcloud_gallery/grid/sources/local_device_media_uri.dart';
import 'package:pizcloud_gallery/viewer/viewer_action.dart'; // new
import 'package:pizcloud_gallery/viewer/viewer_page.dart';
import 'package:pizcloud_gallery/viewer/viewer_cache_manager.dart';
import 'package:pizcloud_gallery/viewer/viewer_session.dart';

class PizGallery extends StatefulWidget {
  final PizGallerySource source;
  final bool enableReuseCell;
  final int scrollToTopSignal;
  final FutureOr<void> Function(MediaItem item)? onViewerShareRequested;
  final FutureOr<void> Function(MediaItem item)? onViewerDeleteRequested;

  // New optional hooks let host customize viewer actions without changing defaults.
  final List<ViewerAction>? viewerActions;
  final bool includeDefaultViewerActions;
  final bool Function(MediaItem item)? canDeleteItem;
  // new
  final FutureOr<void> Function(MediaItem item)? onViewerEditRequested;
  final FutureOr<void> Function(MediaItem item)? onViewerUploadRequested;
  final FutureOr<void> Function(MediaItem item)? onViewerAddToAlbumRequested;
  final bool Function(MediaItem item)? canEditItem;
  final bool Function(MediaItem item)? canUploadItem;
  final bool Function(MediaItem item)? canAddToAlbumItem;
  final bool showDateOverlay;
  final GridDateOverlayTextBuilder? dateOverlayTextBuilder;
  final GallerySortFilterMenuTexts sortFilterMenuTexts;
  // #new

  const PizGallery({
    super.key,
    required this.source,
    this.enableReuseCell = true,
    this.scrollToTopSignal = 0,
    this.onViewerShareRequested,
    this.onViewerDeleteRequested,
    // new
    this.viewerActions,
    this.includeDefaultViewerActions = true,
    this.canDeleteItem,
    this.onViewerEditRequested,
    this.onViewerUploadRequested,
    this.onViewerAddToAlbumRequested,
    this.canEditItem,
    this.canUploadItem,
    this.canAddToAlbumItem,
    this.showDateOverlay = false,
    this.dateOverlayTextBuilder,
    this.sortFilterMenuTexts = const GallerySortFilterMenuTexts.defaults(),
    // #new
  });

  @override
  State<PizGallery> createState() => _PizGalleryState();
}

class _PizGalleryState extends State<PizGallery> with TickerProviderStateMixin {
  static const bool _showDebugBorders = false;
  static const bool _showDebugOutOfRangeCells = _showDebugBorders;
  static const bool _showFpsOverlay = true;
  static const int _prefetchRowsAhead = 10;
  static const int _prefetchRowsBehind = 5;
  static const int _fastScrollPrefetchRowsAhead = 1;
  static const int _fastScrollPrefetchRowsBehind = 0;
  static const int _prefetchThrottleMs = 60;
  static const int _fastScrollThumbEdge = 100;
  static const int _localThumbPrefetchConcurrent = 4;
  static const int _localThumbPrefetchFastScrollConcurrent = 2;
  static const int _localThumbPrefetchBatchSize = 10;
  static const int _localThumbSharedQueueConcurrent = 20;
  static const bool _debugLocalThumbPrefetch = false;
  static const int _debugLocalThumbPrefetchThrottleMs = 120;
  static const int _debugLocalThumbQueueThrottleMs = 120;
  static const int _maxFailedLocalThumbPrefetchKeys = 1200;
  static const int _maxDownloadConcurrent = 20;
  static const int _memoryCacheMaxMb = 120;
  static const int _memoryCacheSize50MaxMb = 120;
  static const int _bytesPerMb = 1024 * 1024;
  static const int _memoryCacheMaxBytes = _memoryCacheMaxMb * _bytesPerMb;
  static const int _memoryCacheSize50MaxBytes =
      _memoryCacheSize50MaxMb * _bytesPerMb;
  static const bool _skipIfWindowUnchanged = true;
  static const bool _enableCompactPending = true;
  static const int _compactFactor = 3;
  static const QueueStrategy _queueStrategy = QueueStrategy.priority2d;
  static LruBytesCache? _sharedBytesCache;

  late GridState grid;
  late MediaDataSource mediaDataSource;
  late FpsMonitor _fpsMonitor;
  late LruBytesCache _bytesCache;
  late DownloadQueue _downloadQueue;
  late GridPrefetchController _prefetchController;
  late TrailingThrottler _prefetchThrottler;
  late GridVisibleCellsBuilder _visibleCellsBuilder;
  late GridGestureController _gestureController;
  late AnimationController _snapController;
  Animation<Matrix4>? _snapAnimation;
  bool _rebuildQueued = false;
  GridWindow? _queuedWindow;
  GridWindow? _lastPrefetchWindow;
  String? _lastLocalPrefetchSignature;
  int _bootstrapToken = 0;
  bool _isCoreInitialized = false;
  bool _isInitialized = false;
  bool _isBootstrapping = true;
  bool _isViewerOpen = false;
  bool _isScrollbarFastScrolling = false;
  bool _queuedAllowRemotePrefetch = true;
  int _lastSyncedViewerIndex = -1;
  Object? _initError;
  List<MediaItem> _allItems = const <MediaItem>[];
  StreamSubscription<List<MediaItem>>? _sourceUpdatesSubscription;
  late LocalThumbPrefetchScheduler _localThumbPrefetchScheduler;
  final LinkedHashMap<String, bool> _failedLocalThumbPrefetchByKey =
      LinkedHashMap<String, bool>();
  GallerySortMode _sortMode = GallerySortMode.addedAtDesc;
  GalleryFilterSelection _filterSelection = const GalleryFilterSelection.all();

  // =======================================================
  // Pool storage
  // =======================================================
  final GridCellPool _cellPool = GridCellPool();

  // =======================================================
  // Scaling lock notifier (NO setState rebuild)
  // =======================================================
  final ValueNotifier<bool> scalingLock = ValueNotifier(false);
  bool _scrolled = false;
  int _lastHandledScrollToTopSignal = 0;

  @override
  void initState() {
    super.initState();
    _lastHandledScrollToTopSignal = widget.scrollToTopSignal;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final int bootstrapToken = ++_bootstrapToken;
    _isBootstrapping = true;
    _initError = null;
    await _sourceUpdatesSubscription?.cancel();
    _sourceUpdatesSubscription = null;
    try {
      final List<MediaItem> items = await widget.source.loadInitial();
      if (!mounted || bootstrapToken != _bootstrapToken) {
        return;
      }
      _initializeCoreResourcesIfNeeded();
      _allItems = List<MediaItem>.unmodifiable(items);
      _applySortAndFilter(notify: false);
      _bindSourceUpdates();
      if (!mounted || bootstrapToken != _bootstrapToken) {
        return;
      }
      setState(() {
        _isBootstrapping = false;
      });
      debugPrint('✅ Grid initialized (${mediaDataSource.length} items)');
    } catch (error, stackTrace) {
      debugPrint('❌ Failed to initialize gallery: $error');
      debugPrint('$stackTrace');
      if (!mounted || bootstrapToken != _bootstrapToken) {
        return;
      }
      setState(() {
        _initError = error;
        _isBootstrapping = false;
      });
    }
  }

  void _initializeCoreResourcesIfNeeded() {
    if (_isCoreInitialized) return;
    _fpsMonitor = FpsMonitor()..start();
    _bytesCache = _sharedBytesCache ??= LruBytesCache(
      maxBytes: _memoryCacheMaxBytes,
      size50MaxBytes: _memoryCacheSize50MaxBytes,
    );
    _downloadQueue = DownloadQueue(
      maxConcurrent: _maxDownloadConcurrent,
      cache: _bytesCache,
      strategy: _queueStrategy,
      enableCompact: _enableCompactPending,
      compactFactor: _compactFactor,
    );
    _isCoreInitialized = true;
  }

  void _bindSourceUpdates() {
    final Stream<List<MediaItem>>? updates = widget.source.watchUpdates();
    if (updates == null) {
      return;
    }
    _sourceUpdatesSubscription = updates.listen(
      _handleSourceItemsUpdate,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('⚠️ Gallery source update error: $error');
        debugPrint('$stackTrace');
      },
    );
  }

  void _handleSourceItemsUpdate(List<MediaItem> nextItems) {
    if (!mounted) {
      return;
    }
    _allItems = List<MediaItem>.unmodifiable(nextItems);
    _applySortAndFilter();
  }

  @override
  void dispose() {
    _sourceUpdatesSubscription?.cancel();
    _sourceUpdatesSubscription = null;
    if (_isInitialized) {
      debugPrint('🧹 Dispose grid + pool');
      _disposeRuntime();
    }
    if (_isCoreInitialized) {
      _fpsMonitor.dispose();
      _downloadQueue.disposeAll();
    }
    _cellPool.clear();

    scalingLock.dispose();
    unawaited(widget.source.dispose());
    super.dispose();
  }

  void _disposeRuntime() {
    if (!_isInitialized) return;
    if (_isScrollbarFastScrolling) {
      _isScrollbarFastScrolling = false;
      grid.setFastScrollActive(false);
    }
    _clearLocalThumbPrefetchState(disposeScheduler: true);
    _prefetchThrottler.dispose();
    _prefetchController.disposeAll();
    _downloadQueue.disposeAll();
    _gestureController.dispose();
    _snapController.dispose();
    grid.dispose();
    _queuedWindow = null;
    _lastPrefetchWindow = null;
    _lastLocalPrefetchSignature = null;
    _rebuildQueued = false;
    _isInitialized = false;
  }

  void _initRuntimeWith(MediaDataSource source) {
    if (_isInitialized) {
      _disposeRuntime();
    }

    mediaDataSource = source;
    grid = GridState(
      totalDataCells: mediaDataSource.length,
      defaultColCount: 5,
      vsync: this,
      onSizeChanged: _scheduleGridRebuild,
    );
    _prefetchController = GridPrefetchController(
      preloadRowsAhead: _prefetchRowsAhead,
      preloadRowsBehind: _prefetchRowsBehind,
      maxRowExclusive: () => grid.rowCount,
      queue: _downloadQueue,
      resolveUrl: _resolvePrefetchUrlAt,
    );
    _prefetchThrottler = TrailingThrottler(_prefetchThrottleMs);
    _localThumbPrefetchScheduler = LocalThumbPrefetchScheduler(
      defaultMaxConcurrent: _localThumbPrefetchConcurrent,
      loader: _resolveLocalThumbPrefetchBytes,
      store: (LocalThumbPrefetchTask task, Uint8List bytes) {
        if (_bytesCache.peek(task.cacheKey) == null) {
          _bytesCache.put(task.cacheKey, bytes);
        }
      },
      isCached: (String cacheKey) => _bytesCache.peek(cacheKey) != null,
      isFailed: _isFailedLocalThumbPrefetchKey,
      markFailed: _markFailedLocalThumbPrefetchKey,
      debugEnabled: _debugLocalThumbPrefetch,
      debugName: 'local_thumb_scheduler',
      debugLogThrottleMs: _debugLocalThumbPrefetchThrottleMs,
    );
    LocalThumbRequestQueue.instance.configure(
      maxConcurrent: _localThumbSharedQueueConcurrent,
      peekCachedBytes: (String cacheKey) => _bytesCache.peek(cacheKey),
      storeCachedBytes: (String cacheKey, Uint8List bytes) {
        if (cacheKey.isEmpty || bytes.isEmpty) {
          return;
        }
        if (_bytesCache.peek(cacheKey) == null) {
          _bytesCache.put(cacheKey, bytes);
        }
      },
      debugEnabled: _debugLocalThumbPrefetch,
      debugName: 'local_thumb_queue',
      debugLogThrottleMs: _debugLocalThumbQueueThrottleMs,
    );
    _visibleCellsBuilder = GridVisibleCellsBuilder(
      grid: grid,
      mediaDataSource: mediaDataSource,
      cellPool: _cellPool,
      showDebugOutOfRangeCells: _showDebugOutOfRangeCells,
      bytesCache: _bytesCache,
    );
    _gestureController = GridGestureController(
      grid: grid,
      scalingLock: scalingLock,
      onScaleEnd: _handleSnapAfterScale,
      onDebugTripleTouch: grid.debugPrintTable,
    );
    grid.init();
    _snapController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addListener(() {
          final next = _snapAnimation?.value;
          if (next != null) {
            grid.transformController.value = next;
          }
        });
    _scrolled = false;
    _isInitialized = true;
    _cellPool.clear();
  }

  void _applySortAndFilter({bool notify = true}) {
    final List<MediaItem> viewItems = _buildViewItems();
    _initRuntimeWith(MediaDataSource(viewItems));
    if (notify && mounted) {
      setState(() {});
    }
  }

  List<MediaItem> _buildViewItems() {
    final Iterable<MediaItem> filtered = _allItems.where(
      _matchesCurrentFilters,
    );
    final List<MediaItem> values = filtered.toList(growable: false);
    values.sort((a, b) {
      final DateTime? left = switch (_sortMode) {
        GallerySortMode.createdAtDesc => a.createdAt,
        GallerySortMode.addedAtDesc => a.addedAt,
      };
      final DateTime? right = switch (_sortMode) {
        GallerySortMode.createdAtDesc => b.createdAt,
        GallerySortMode.addedAtDesc => b.addedAt,
      };
      final int byDate = _compareDateDesc(left, right);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });
    return values;
  }

  bool _matchesCurrentFilters(MediaItem item) {
    final bool matchType = item.isPhoto
        ? _filterSelection.includePhotos
        : _filterSelection.includeVideos;
    if (!matchType) {
      return false;
    }
    final bool matchSource = item.isLocal
        ? _filterSelection.includeOnDevice
        : _filterSelection.includeCloud;
    return matchSource;
  }

  int _compareDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  void _onMenuSelected(GalleryMenuAction action) {
    final GallerySortMode nextSortMode = switch (action) {
      GalleryMenuAction.sortCreatedAt => GallerySortMode.createdAtDesc,
      GalleryMenuAction.sortAddedAt => GallerySortMode.addedAtDesc,
      _ => _sortMode,
    };
    final GalleryFilterSelection nextFilterSelection;
    if (action == GalleryMenuAction.filterReset) {
      nextFilterSelection = const GalleryFilterSelection.all();
    } else if (_filterSelection.isAll) {
      // From "Show all", first tap should narrow to one chosen axis value.
      nextFilterSelection = switch (action) {
        GalleryMenuAction.filterTogglePhoto => const GalleryFilterSelection(
          includePhotos: true,
          includeVideos: false,
          includeOnDevice: true,
          includeCloud: true,
        ),
        GalleryMenuAction.filterToggleVideo => const GalleryFilterSelection(
          includePhotos: false,
          includeVideos: true,
          includeOnDevice: true,
          includeCloud: true,
        ),
        GalleryMenuAction.filterToggleOnDevice => const GalleryFilterSelection(
          includePhotos: true,
          includeVideos: true,
          includeOnDevice: true,
          includeCloud: false,
        ),
        GalleryMenuAction.filterToggleCloud => const GalleryFilterSelection(
          includePhotos: true,
          includeVideos: true,
          includeOnDevice: false,
          includeCloud: true,
        ),
        _ => _filterSelection,
      };
    } else {
      nextFilterSelection = switch (action) {
        GalleryMenuAction.filterTogglePhoto => _filterSelection.copyWith(
          includePhotos: !_filterSelection.includePhotos,
        ),
        GalleryMenuAction.filterToggleVideo => _filterSelection.copyWith(
          includeVideos: !_filterSelection.includeVideos,
        ),
        GalleryMenuAction.filterToggleOnDevice => _filterSelection.copyWith(
          includeOnDevice: !_filterSelection.includeOnDevice,
        ),
        GalleryMenuAction.filterToggleCloud => _filterSelection.copyWith(
          includeCloud: !_filterSelection.includeCloud,
        ),
        _ => _filterSelection,
      };
    }
    final bool changed =
        nextSortMode != _sortMode || nextFilterSelection != _filterSelection;
    if (!changed || !_isInitialized) return;
    _sortMode = nextSortMode;
    _filterSelection = nextFilterSelection;
    _applySortAndFilter();
  }

  Future<void> _openViewerAtDataIndex(
    int dataIndex, {
    required String initialHeroTag,
  }) async {
    if (!_isInitialized) return;
    if (dataIndex < 0 || dataIndex >= mediaDataSource.length) return;
    bool initialOriginalReady = false;
    final MediaItem? item = mediaDataSource.itemAtDataIndex(dataIndex);
    if (item != null && !item.isVideo && _isNetworkUrl(item.originalUrl)) {
      final int decodeWidth = _viewerDecodeWidthForItem(item);
      final int? decodeHeight = _viewerDecodeHeightForItem(item, decodeWidth);
      final ImageProvider<Object> provider = ViewerCacheManager.providerFor(
        item.originalUrl,
        maxWidth: decodeWidth,
        maxHeight: decodeHeight,
        debugIndex: dataIndex,
      );
      final ImageCacheStatus? cacheStatus = await provider.obtainCacheStatus(
        configuration: createLocalImageConfiguration(context),
      );
      final bool inMemoryCache = cacheStatus?.tracked ?? false;
      final bool inDiskCache = await ViewerCacheManager.instance.isCachedOnDisk(
        item.originalUrl,
        maxWidth: decodeWidth,
        maxHeight: decodeHeight,
      );
      if (!mounted) return;
      if (inMemoryCache || inDiskCache) {
        try {
          await precacheImage(provider, context);
          initialOriginalReady = true;
        } catch (_) {
          initialOriginalReady = inMemoryCache;
        }
        if (!mounted) return;
      }
    }
    if (mounted && !_isViewerOpen) {
      setState(() {
        _isViewerOpen = true;
      });
    }
    _lastSyncedViewerIndex = -1;
    _onViewerVisibleIndexChanged(dataIndex);
    try {
      await ViewerPage.open(
        context,
        session: ViewerSession(
          items: mediaDataSource.items,
          initialIndex: dataIndex,
          initialOriginalReady: initialOriginalReady,
          initialHeroTag: initialHeroTag,
          onVisibleIndexChanged: _onViewerVisibleIndexChanged,
          onShareRequested: _handleViewerShareRequested,
          onDeleteRequested: widget.onViewerDeleteRequested == null
              ? null
              : _handleViewerDeleteRequested,
          // new
          onEditRequested: widget.onViewerEditRequested == null
              ? null
              : _handleViewerEditRequested,
          onUploadRequested: widget.onViewerUploadRequested == null
              ? null
              : _handleViewerUploadRequested,
          onAddToAlbumRequested: widget.onViewerAddToAlbumRequested == null
              ? null
              : _handleViewerAddToAlbumRequested,
          // #new
          viewerActions: widget.viewerActions,
          includeDefaultViewerActions: widget.includeDefaultViewerActions,
          canDeleteItem: widget.canDeleteItem,
          // new
          canEditItem: widget.canEditItem,
          canUploadItem: widget.canUploadItem,
          canAddToAlbumItem: widget.canAddToAlbumItem,
          // #new
        ),
      );
    } finally {
      _lastSyncedViewerIndex = -1;
      if (mounted && _isViewerOpen) {
        setState(() {
          _isViewerOpen = false;
        });
      }
    }
  }

  void _onViewerVisibleIndexChanged(int index) {
    if (!_isInitialized || !_isViewerOpen) return;
    if (index == _lastSyncedViewerIndex) return;
    _lastSyncedViewerIndex = index;
    if (grid.isDataIndexInViewport(index)) {
      return;
    }
    grid.ensureDataIndexVisible(
      index,
      alignInViewport: 0.45,
      hysteresisRows: 1.25,
    );
  }

  Future<void> _handleViewerShareRequested(MediaItem item) async {
    await widget.onViewerShareRequested?.call(item);
  }

  Future<void> _handleViewerDeleteRequested(MediaItem item) async {
    // Host executes the real delete first (local/cloud/DB/business rules).
    await widget.onViewerDeleteRequested!.call(item);
    // After host succeeds, update gallery source snapshot/UI.
    await widget.source.removeItem(item);
    if (!mounted) return;
    final int previousLength = _allItems.length;
    final List<MediaItem> nextItems = _allItems
        .where((MediaItem value) => value.id != item.id)
        .toList(growable: false);
    if (nextItems.length == previousLength) {
      return;
    }
    _allItems = List<MediaItem>.unmodifiable(nextItems);
    _applySortAndFilter();
  }

  // new
  Future<void> _handleViewerEditRequested(MediaItem item) async {
    await widget.onViewerEditRequested?.call(item);
  }

  Future<void> _handleViewerUploadRequested(MediaItem item) async {
    await widget.onViewerUploadRequested?.call(item);
  }

  Future<void> _handleViewerAddToAlbumRequested(MediaItem item) async {
    await widget.onViewerAddToAlbumRequested?.call(item);
  }
  // #new

  bool _isNetworkUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  int _viewerDecodeWidthForItem(MediaItem item) {
    final int decodeWidth = ViewerCacheManager.decodeWidthForContext(context);
    final int? originalWidth = item.width;
    if (originalWidth == null || originalWidth <= 0) {
      return decodeWidth;
    }
    return decodeWidth.clamp(1, originalWidth).toInt();
  }

  int? _viewerDecodeHeightForItem(MediaItem item, int decodeWidth) {
    final int? originalWidth = item.width;
    final int? originalHeight = item.height;
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

  Widget _buildSortFilterMenuButton() {
    return Positioned(
      // new
      // top: 8,
      // right: 8,
      right: 20,
      bottom: 14,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x66FFFFFF), width: 1),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        // #new
        child: GallerySortFilterMenuButton(
          sortMode: _sortMode,
          filterSelection: _filterSelection,
          onSelected: _onMenuSelected,
          texts: widget.sortFilterMenuTexts, // new
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PizGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableReuseCell && !widget.enableReuseCell) {
      _cellPool.clear();
    }
    if (oldWidget.source != widget.source) {
      unawaited(oldWidget.source.dispose());
      setState(() {
        _isBootstrapping = true;
        _initError = null;
      });
      _bootstrap();
    }
    if (oldWidget.scrollToTopSignal != widget.scrollToTopSignal &&
        _lastHandledScrollToTopSignal != widget.scrollToTopSignal) {
      _lastHandledScrollToTopSignal = widget.scrollToTopSignal;
      _scrollToLockTopOffset();
    }
  }

  void _scrollToLockTopOffset() {
    if (!_isInitialized) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isInitialized || !grid.verticalController.hasClients) {
        return;
      }
      final ScrollPosition position = grid.verticalController.position;
      final ({double lockTopOffset, double lockBottomOffset}) locks = grid
          .getScrollLockOffsets();
      final double target = locks.lockTopOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((position.pixels - target).abs() < 0.5) {
        return;
      }
      unawaited(
        grid.verticalController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _scheduleGridRebuild() {
    if (!mounted || _rebuildQueued) return;
    _rebuildQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _scheduleQueuePrefetch(
    GridWindow window, {
    required bool allowRemotePrefetch,
  }) {
    _queuedWindow = window;
    _queuedAllowRemotePrefetch = allowRemotePrefetch;
    _prefetchThrottler.schedule(_triggerQueuePrefetch);
  }

  void _triggerQueuePrefetch() {
    final GridWindow? window = _queuedWindow;
    if (window == null || !mounted) return;
    final bool isFastScrolling = _isScrollbarFastScrolling;
    if (!isFastScrolling && _queuedAllowRemotePrefetch) {
      if (_skipIfWindowUnchanged &&
          _lastPrefetchWindow != null &&
          window.sameAs(_lastPrefetchWindow!)) {
        _prefetchLocalThumbs(window);
        return;
      }
      _lastPrefetchWindow = window;
      _prefetchController.update(window);
    }
    _prefetchLocalThumbs(
      window,
      rowsAhead: isFastScrolling
          ? _fastScrollPrefetchRowsAhead
          : _prefetchRowsAhead,
      rowsBehind: isFastScrolling
          ? _fastScrollPrefetchRowsBehind
          : _prefetchRowsBehind,
      thumbEdgeOverride: isFastScrolling ? _fastScrollThumbEdge : null,
    );
  }

  void _handleScrollbarDragStateChanged(bool isDragging) {
    if (_isScrollbarFastScrolling == isDragging) {
      return;
    }
    _isScrollbarFastScrolling = isDragging;
    if (_isInitialized) {
      grid.setFastScrollActive(isDragging);
      if (!isDragging) {
        _prefetchThrottler.schedule(_triggerQueuePrefetch);
      }
    }
    _scheduleGridRebuild();
  }

  String? _resolvePrefetchUrlAt(int row, int col) {
    final int index = _resolveDataIndexAtWindowCell(row, col);
    if (index < 0 || index >= grid.totalDataCells) {
      return null;
    }

    final mediaItem = mediaDataSource.itemAtDataIndex(index);
    if (mediaItem == null) {
      return null;
    }
    if (mediaItem.isLocal) {
      return null;
    }

    final double renderScale = grid.getCurrentScale();
    final bool preferTargetColCount = grid.scaleDirection != 0;
    return mediaItem.pickGridThumbAdaptive(
      cellSize: grid.cellSize,
      scale: renderScale,
      currentColCount: grid.currentColCount,
      targetColCount: grid.targetColCount,
      preferTargetColCount: preferTargetColCount,
    );
  }

  int _resolveDataIndexAtWindowCell(int row, int col) {
    final int logicalRow = grid.baseRow + row;
    return logicalRow * grid.targetColCount +
        col -
        grid.baseCells[grid.targetColCount];
  }

  void _prefetchLocalThumbs(
    GridWindow window, {
    int rowsAhead = _prefetchRowsAhead,
    int rowsBehind = _prefetchRowsBehind,
    int? thumbEdgeOverride,
  }) {
    if (!_isInitialized) {
      return;
    }
    final String signature = [
      window.firstRow,
      window.lastRow,
      window.firstCol,
      window.lastCol,
      rowsAhead,
      rowsBehind,
      thumbEdgeOverride ?? -1,
      grid.currentColCount,
      grid.targetColCount,
      grid.scaleDirection,
      (grid.getCurrentScale() * 10).round(),
    ].join(':');
    if (_skipIfWindowUnchanged && _lastLocalPrefetchSignature == signature) {
      return;
    }
    _lastLocalPrefetchSignature = signature;

    final int maxRows = grid.rowCount;
    if (maxRows <= 0) {
      LocalThumbRequestQueue.instance.replaceWantedVisibleKeys(
        const <String>[],
      );
      LocalThumbRequestQueue.instance.replaceWantedPrefetchKeys(
        const <String>[],
      );
      _localThumbPrefetchScheduler.clear();
      return;
    }
    final int safeRowsBehind = rowsBehind < 0 ? 0 : rowsBehind;
    final int safeRowsAhead = rowsAhead < 0 ? 0 : rowsAhead;
    final int startRow = math.max(0, window.firstRow - safeRowsBehind);
    final int endRowExclusive = math.min(
      maxRows,
      window.lastRow + safeRowsAhead,
    );
    final int startCol = window.firstCol;
    final int endColExclusive = window.lastCol;
    if (endRowExclusive <= startRow || endColExclusive <= startCol) {
      LocalThumbRequestQueue.instance.replaceWantedVisibleKeys(
        const <String>[],
      );
      LocalThumbRequestQueue.instance.replaceWantedPrefetchKeys(
        const <String>[],
      );
      _localThumbPrefetchScheduler.clear();
      return;
    }

    final double centerRow = (window.firstRow + window.lastRow - 1) / 2;
    final double centerCol = (window.firstCol + window.lastCol - 1) / 2;
    final Map<String, LocalThumbPrefetchTask> wantedByKey =
        <String, LocalThumbPrefetchTask>{};
    final Set<String> visibleWantedKeys = <String>{};
    final Map<String, LocalThumbRequest> visibleRequestsByKey =
        <String, LocalThumbRequest>{};

    for (int row = startRow; row < endRowExclusive; row++) {
      for (int col = startCol; col < endColExclusive; col++) {
        final double basePriority =
            (row - centerRow).abs() * 8 + (col - centerCol).abs();
        final Iterable<LocalThumbPrefetchTask> tasks =
            _resolveLocalPrefetchTasksAt(
              row,
              col,
              thumbEdgeOverride: thumbEdgeOverride,
              basePriority: basePriority,
              isInViewportCell:
                  row >= window.firstRow &&
                  row < window.lastRow &&
                  col >= window.firstCol &&
                  col < window.lastCol,
            );
        for (final LocalThumbPrefetchTask task in tasks) {
          if (task.isInViewport) {
            visibleWantedKeys.add(task.cacheKey);
            final LocalThumbRequest visibleRequest = LocalThumbRequest(
              cacheKey: task.cacheKey,
              dataIndex: task.dataIndex,
              assetId: task.assetId,
              edge: task.edge,
              isVideo: task.isVideo,
              priority: task.priority,
              isInViewport: true,
              source: LocalThumbRequestSource.visible,
            );
            final LocalThumbRequest? existingVisible =
                visibleRequestsByKey[task.cacheKey];
            if (existingVisible == null ||
                visibleRequest.priority < existingVisible.priority) {
              visibleRequestsByKey[task.cacheKey] = visibleRequest;
            }
          }
          final LocalThumbPrefetchTask? existing = wantedByKey[task.cacheKey];
          if (existing == null ||
              (task.isInViewport && !existing.isInViewport) ||
              (task.isInViewport == existing.isInViewport &&
                  task.priority < existing.priority)) {
            wantedByKey[task.cacheKey] = task;
          }
        }
      }
    }
    LocalThumbRequestQueue.instance.replaceWantedVisibleKeys(visibleWantedKeys);
    for (final LocalThumbRequest request in visibleRequestsByKey.values) {
      LocalThumbRequestQueue.instance.enqueue(request);
    }
    LocalThumbRequestQueue.instance.replaceWantedPrefetchKeys(wantedByKey.keys);
    _localThumbPrefetchScheduler.updateWanted(
      wantedByKey.values,
      maxConcurrent: _isScrollbarFastScrolling
          ? _localThumbPrefetchFastScrollConcurrent
          : _localThumbPrefetchConcurrent,
      maxBatchSize: _localThumbPrefetchBatchSize,
    );
  }

  Iterable<LocalThumbPrefetchTask> _resolveLocalPrefetchTasksAt(
    int row,
    int col, {
    required int? thumbEdgeOverride,
    required double basePriority,
    required bool isInViewportCell,
  }) {
    final int index = _resolveDataIndexAtWindowCell(row, col);
    if (index < 0 || index >= grid.totalDataCells) {
      return const <LocalThumbPrefetchTask>[];
    }
    final MediaItem? mediaItem = mediaDataSource.itemAtDataIndex(index);
    if (mediaItem == null || !mediaItem.isLocal) {
      return const <LocalThumbPrefetchTask>[];
    }

    if (thumbEdgeOverride != null && thumbEdgeOverride > 0) {
      final String? assetId = _resolveLocalAssetId(mediaItem);
      if (assetId == null || assetId.isEmpty) {
        return const <LocalThumbPrefetchTask>[];
      }
      final String source = LocalDeviceMediaUri.buildThumbUri(
        assetId: assetId,
        edge: thumbEdgeOverride,
      );
      final LocalThumbPrefetchTask? task = _parseLocalThumbPrefetchTask(
        mediaItem: mediaItem,
        dataIndex: index,
        source: source,
        priority: basePriority,
        isInViewportCell: isInViewportCell,
      );
      if (task == null) {
        return const <LocalThumbPrefetchTask>[];
      }
      return <LocalThumbPrefetchTask>[task];
    }

    final double renderScale = grid.getCurrentScale();
    final bool preferTargetColCount = grid.scaleDirection != 0;
    final Map<String, LocalThumbPrefetchTask> tasksByKey =
        <String, LocalThumbPrefetchTask>{};
    final String? primarySource = mediaItem.pickGridThumbAdaptive(
      cellSize: grid.cellSize,
      scale: renderScale,
      currentColCount: grid.currentColCount,
      targetColCount: grid.targetColCount,
      preferTargetColCount: preferTargetColCount,
    );
    final LocalThumbPrefetchTask? primaryTask = _parseLocalThumbPrefetchTask(
      mediaItem: mediaItem,
      dataIndex: index,
      source: primarySource,
      priority: basePriority,
      isInViewportCell: isInViewportCell,
    );
    if (primaryTask != null) {
      tasksByKey[primaryTask.cacheKey] = primaryTask;
    }

    if (grid.scaleDirection != 0) {
      final String? secondarySource = mediaItem.pickGridThumbAdaptive(
        cellSize: grid.cellSize,
        scale: renderScale,
        currentColCount: grid.currentColCount,
        targetColCount: grid.targetColCount,
        preferTargetColCount: !preferTargetColCount,
      );
      final LocalThumbPrefetchTask? secondaryTask =
          _parseLocalThumbPrefetchTask(
            mediaItem: mediaItem,
            dataIndex: index,
            source: secondarySource,
            priority: basePriority + 0.25,
            isInViewportCell: isInViewportCell,
          );
      if (secondaryTask != null) {
        final LocalThumbPrefetchTask? existing =
            tasksByKey[secondaryTask.cacheKey];
        if (existing == null || secondaryTask.priority < existing.priority) {
          tasksByKey[secondaryTask.cacheKey] = secondaryTask;
        }
      }
    }

    if (tasksByKey.isEmpty) {
      return const <LocalThumbPrefetchTask>[];
    }
    return tasksByKey.values.toList(growable: false);
  }

  String? _resolveLocalAssetId(MediaItem mediaItem) {
    final String? fromOriginal = LocalDeviceMediaUri.parseOriginalAssetId(
      mediaItem.originalUrl,
    );
    if (fromOriginal != null && fromOriginal.isNotEmpty) {
      return fromOriginal;
    }
    final String? fromPreview = LocalDeviceMediaUri.parseThumbUri(
      mediaItem.previewUrl ?? '',
    )?.assetId;
    if (fromPreview != null && fromPreview.isNotEmpty) {
      return fromPreview;
    }
    final String? fromSize100 = LocalDeviceMediaUri.parseThumbUri(
      mediaItem.thumbnails.size100,
    )?.assetId;
    if (fromSize100 != null && fromSize100.isNotEmpty) {
      return fromSize100;
    }
    return null;
  }

  LocalThumbPrefetchTask? _parseLocalThumbPrefetchTask({
    required MediaItem mediaItem,
    required int dataIndex,
    required String? source,
    required double priority,
    required bool isInViewportCell,
  }) {
    final String normalizedSource = source?.trim() ?? '';
    if (normalizedSource.isEmpty) {
      return null;
    }
    final ({String assetId, int edge})? thumbUri =
        LocalDeviceMediaUri.parseThumbUri(normalizedSource);
    if (thumbUri == null) {
      return null;
    }
    return LocalThumbPrefetchTask(
      cacheKey: LocalDeviceMediaUri.buildTypedThumbCacheKey(
        normalizedSource,
        isVideo: mediaItem.isVideo,
      ),
      dataIndex: dataIndex,
      assetId: thumbUri.assetId,
      edge: thumbUri.edge,
      isVideo: mediaItem.isVideo,
      priority: priority,
      isInViewport: isInViewportCell,
    );
  }

  Future<Uint8List?> _resolveLocalThumbPrefetchBytes(
    LocalThumbPrefetchTask request,
  ) async {
    return LocalThumbRequestQueue.instance.request(
      LocalThumbRequest(
        cacheKey: request.cacheKey,
        dataIndex: request.dataIndex,
        assetId: request.assetId,
        edge: request.edge,
        isVideo: request.isVideo,
        priority: request.priority,
        isInViewport: request.isInViewport,
        source: LocalThumbRequestSource.prefetch,
      ),
    );
  }

  bool _isFailedLocalThumbPrefetchKey(String key) {
    if (key.isEmpty) {
      return false;
    }
    final bool? failed = _failedLocalThumbPrefetchByKey.remove(key);
    if (failed == null) {
      return false;
    }
    _failedLocalThumbPrefetchByKey[key] = failed;
    return failed;
  }

  void _markFailedLocalThumbPrefetchKey(String key) {
    if (key.isEmpty) {
      return;
    }
    _failedLocalThumbPrefetchByKey.remove(key);
    _failedLocalThumbPrefetchByKey[key] = true;
    while (_failedLocalThumbPrefetchByKey.length >
        _maxFailedLocalThumbPrefetchKeys) {
      _failedLocalThumbPrefetchByKey.remove(
        _failedLocalThumbPrefetchByKey.keys.first,
      );
    }
  }

  void _clearLocalThumbPrefetchState({bool disposeScheduler = false}) {
    LocalThumbRequestQueue.instance.replaceWantedVisibleKeys(const <String>[]);
    LocalThumbRequestQueue.instance.replaceWantedPrefetchKeys(const <String>[]);
    if (disposeScheduler) {
      _localThumbPrefetchScheduler.dispose();
    } else {
      _localThumbPrefetchScheduler.clear();
    }
    _failedLocalThumbPrefetchByKey.clear();
  }

  // Decide snap target based on last scale direction and thresholds
  Future<void> _handleSnapAfterScale() async {
    // debugPrint('_handleSnapAfterScale');
    final dir = grid.scaleDirection;
    // if (dir == 0) return;

    final double scale = grid.transformController.value.getMaxScaleOnAxis();
    final decision = GridStateHelper.resolveScaleDecision(
      scale: scale,
      currentColCount: grid.currentColCount,
      scaleDirection: dir,
    );
    final double target = decision.snapScale;
    final int scaleCol = decision.colCount;
    // grid.updateBaseCell(scaleCol);
    // if (scaleCol != grid.currentColCount) {
    //   grid.currentColCount = scaleCol;
    // }
    // grid.jumpToLogicalRow(0);
    // grid.clampScrollToFirstCell();
    grid.jumpToFirstDataRowIfContentShort();
    grid.clampScrollToFirstCellWhenContentShort();
    // grid.updateBaseCell(scaleCol);
    // grid.debugPrintTable();
    await grid.animateScaleTo(target, scaleCol);
    grid.clampScrollToFirstCellWhenContentShort();
    // grid.updateViewportFirstCol();
    // grid.updateBaseCell(scaleCol);
    // _animateScaleTo(target);
    if (!mounted) return;
    if (scaleCol != grid.currentColCount) {
      // grid.currentColCount = scaleCol;
    }
    grid.resetScaleDirection();
    setState(() {});
  }

  Widget _withDebugBorder(Widget child, Color color) {
    if (!_showDebugBorders) return child;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
      child: child,
    );
  }

  Widget _buildLoadingState() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildErrorState(Object error) {
    return Center(child: Text('Failed to load gallery source: $error'));
  }

  Widget _buildEmptyState(GridAppearancePalette palette) {
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: palette.gridBackground)),
        const Center(child: Text('No data for the current filter')),
        _buildSortFilterMenuButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final GridAppearancePalette palette = GridAppearancePalette.of(context);
    if (_isBootstrapping) {
      return _buildLoadingState();
    }
    if (_initError != null) {
      return _buildErrorState(_initError!);
    }
    if (!_isInitialized) {
      return _buildLoadingState();
    }
    if (mediaDataSource.isEmpty) {
      return _buildEmptyState(palette);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit exactly 5 columns initially; skip if layout not ready.
        final double maxW = constraints.maxWidth;
        if (maxW <= 0 || !maxW.isFinite) {
          debugPrint(
            '⚠️ LayoutBuilder width not ready, keep previous cellSize',
          );
          return const SizedBox.shrink();
        }
        if (!_scrolled && !mediaDataSource.isEmpty) {
          _scrolled = true;
          grid.prependVirtualRows(1000);
          grid.appendVirtualRows(1000);
        }
        grid.cellSize = maxW / grid.defaultColCount;

        final gridWidth = grid.defaultColCount * grid.cellSize;
        // final gridHeight = grid.getRowCount() * grid.cellSize;

        final viewportWidth = maxW;
        final viewportHeight = constraints.maxHeight;
        grid.updateViewportSize(Size(viewportWidth, viewportHeight));

        return ValueListenableBuilder<bool>(
          valueListenable: scalingLock,
          builder: (context, scaling, child) {
            return Listener(
              // =======================================================
              // Pointer tracking (lock scroll when pinch zoom)
              // =======================================================
              onPointerDown: _gestureController.onPointerDown,
              onPointerMove: _gestureController.onPointerMove,
              onPointerUp: _gestureController.onPointerUp,
              onPointerCancel: (_) => _gestureController.onPointerCancel(),

              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: palette.gridBackground),
                  ),
                  Positioned.fill(
                    child: InteractiveViewer(
                      // boundaryMargin: const EdgeInsets.all(double.infinity),
                      constrained: true,
                      key: grid.containerKey,
                      transformationController: grid.transformController,
                      panEnabled: false,
                      // Only enable pinch-zoom when there are >=2 touches;
                      // single-finger drags go straight to the scroll views.
                      scaleEnabled: scaling,
                      minScale: 1,
                      maxScale: 5.1,
                      onInteractionStart: (_) {},
                      onInteractionUpdate:
                          _gestureController.onInteractionUpdate,
                      onInteractionEnd: (_) {},

                      child: ScrollConfiguration(
                        behavior: const ScrollBehavior().copyWith(
                          overscroll: false,
                        ),
                        child: _withDebugBorder(
                          SingleChildScrollView(
                            controller: grid.verticalController,
                            scrollDirection: Axis.vertical,
                            physics: scaling
                                ? const NeverScrollableScrollPhysics()
                                : SnapScrollPhysics(
                                    lockOffsetsResolver:
                                        grid.getScrollLockOffsets,
                                  ),
                            child: _withDebugBorder(
                              SingleChildScrollView(
                                controller: grid.horizontalController,
                                scrollDirection: Axis.horizontal,
                                physics: scaling
                                    ? const NeverScrollableScrollPhysics()
                                    : const ClampingScrollPhysics(),
                                child: _withDebugBorder(
                                  SizedBox(
                                    width: gridWidth,
                                    height: grid.gridHeight(),
                                    key: grid.gridKey,
                                    child: _withDebugBorder(
                                      AnimatedBuilder(
                                        animation: Listenable.merge([
                                          grid.scrollOffset,
                                          grid.transformController,
                                        ]),
                                        builder: (context, _) {
                                          final bool isFastScrolling =
                                              _isScrollbarFastScrolling;
                                          final liveWindow = grid
                                              .getVisibleWindow(
                                                viewportWidth,
                                                viewportHeight,
                                                extraRowsAhead: isFastScrolling
                                                    ? 0
                                                    : 2,
                                                extraRowsBehind: isFastScrolling
                                                    ? 0
                                                    : 1,
                                              );
                                          final GridWindow renderWindow =
                                              liveWindow;
                                          if (!_isViewerOpen) {
                                            _scheduleQueuePrefetch(
                                              liveWindow,
                                              allowRemotePrefetch:
                                                  !scaling &&
                                                  !_isScrollbarFastScrolling,
                                            );
                                          }
                                          if (!isFastScrolling) {
                                            return _visibleCellsBuilder
                                                .buildVisibleCells(
                                                  window: liveWindow,
                                                  enableReuseCell:
                                                      widget.enableReuseCell,
                                                  lightweightMode: false,
                                                  thumbEdgeOverride: null,
                                                  onDataIndexTap:
                                                      (
                                                        dataIndex,
                                                        thumbUrl,
                                                        heroTag,
                                                      ) =>
                                                          _openViewerAtDataIndex(
                                                            dataIndex,
                                                            initialHeroTag:
                                                                heroTag,
                                                          ),
                                                );
                                          }
                                          return Stack(
                                            children: [
                                              _visibleCellsBuilder
                                                  .buildVisibleCells(
                                                    window: liveWindow,
                                                    enableReuseCell:
                                                        widget.enableReuseCell,
                                                    lightweightMode: true,
                                                    thumbEdgeOverride: null,
                                                    onDataIndexTap:
                                                        (
                                                          dataIndex,
                                                          thumbUrl,
                                                          heroTag,
                                                        ) =>
                                                            _openViewerAtDataIndex(
                                                              dataIndex,
                                                              initialHeroTag:
                                                                  heroTag,
                                                            ),
                                                  ),
                                              _visibleCellsBuilder
                                                  .buildVisibleCells(
                                                    window: renderWindow,
                                                    enableReuseCell:
                                                        widget.enableReuseCell,
                                                    lightweightMode: false,
                                                    thumbEdgeOverride:
                                                        _fastScrollThumbEdge,
                                                    onDataIndexTap:
                                                        (
                                                          dataIndex,
                                                          thumbUrl,
                                                          heroTag,
                                                        ) =>
                                                            _openViewerAtDataIndex(
                                                              dataIndex,
                                                              initialHeroTag:
                                                                  heroTag,
                                                            ),
                                                  ),
                                            ],
                                          );
                                        },
                                      ),
                                      Colors.red,
                                    ),
                                  ),
                                  Colors.black,
                                ),
                              ),
                              Colors.blue,
                            ),
                          ),
                          Colors.yellow,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    // new
                    // top: 56,
                    // bottom: 8,
                    // right: -1,
                    top: 30,
                    bottom: 36,
                    right: -5,
                    // #new
                    child: RealDataScrollbar(
                      grid: grid,
                      viewportHeight: viewportHeight,
                      interactive: !scaling,
                      enableTrackGestures: false,
                      onDragStateChanged: _handleScrollbarDragStateChanged,
                    ),
                  ),
                  if (_showFpsOverlay)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: FpsBadge(monitor: _fpsMonitor),
                    ),
                  // new
                  if (widget.showDateOverlay)
                    Positioned(
                      top: 8,
                      left: _showFpsOverlay ? 96 : 8,
                      child: GridDateOverlay(
                        grid: grid,
                        mediaDataSource: mediaDataSource,
                        textBuilder: widget.dateOverlayTextBuilder,
                        preferAddedAt: _sortMode == GallerySortMode.addedAtDesc,
                      ),
                    ),
                  // #new
                  _buildSortFilterMenuButton(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
