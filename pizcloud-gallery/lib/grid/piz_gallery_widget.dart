import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:pizcloud_gallery/grid/download_queue.dart';
import 'package:pizcloud_gallery/grid/fps_overlay.dart';
import 'package:pizcloud_gallery/grid/gallery_date_browse_overlay.dart'; // new
import 'package:pizcloud_gallery/grid/grid_date_overlay.dart'; // new
import 'package:pizcloud_gallery/grid/gallery_sort_filter_menu.dart';
import 'package:pizcloud_gallery/grid/cell_data.dart'; // new
import 'package:pizcloud_gallery/grid/grid_cell.dart'; // new
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
import 'package:pizcloud_gallery/grid/storage_indicator.dart'; // new
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
  final bool showDateBrowseOverlay;
  final GalleryDateBrowseTexts dateBrowseTexts;
  final bool showStorageIndicator; // new
  final GridStorageIndicatorResolver? storageIndicatorResolver; // new
  final bool showScrollbarDateHint; // new
  final bool enableMultiSelect; // new
  final bool showSelectModeButton; // new
  final int clearSelectionSignal; // new
  final ValueChanged<List<MediaItem>>? onSelectionChanged; // new
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
    this.showDateBrowseOverlay = false,
    this.dateBrowseTexts = const GalleryDateBrowseTexts.defaults(),
    this.showStorageIndicator = false,
    this.storageIndicatorResolver,
    this.showScrollbarDateHint = false,
    this.enableMultiSelect = false,
    this.showSelectModeButton = false,
    this.clearSelectionSignal = 0,
    this.onSelectionChanged,
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
  // static const double _dateBrowseRowHeight = 96;
  static const double _dateBrowseRowHeight = 124; // new
  static const double _dateBrowseRowSpacing = 10; // new
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
  static const Duration _jumpTargetIndicatorDuration = Duration(
    milliseconds: 2800,
  ); // new
  static const Duration _selectedYearAnchorPulseDuration = Duration(
    milliseconds: 2000,
  ); // new
  static const Duration _pendingMonthBrowseScrollTimeout = Duration(
    milliseconds: 2000,
  ); // new
  static const Duration _scrollbarDateHintHideDelay = Duration(
    milliseconds: 320,
  ); // new
  static const double _pendingMonthBrowseTopTolerance = 0.5; // new
  static const double _dateBrowseListBaseBottomPadding = 110; // new
  static const double _dateBrowseTopAlignPaddingSlack = 8; // new
  static const double _scrollbarDateHintBubbleHeight = 30; // new
  static const double _scrollbarDateHintBubbleGap = 8; // new
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
  // new
  GalleryDateBrowseMode _dateBrowseMode = GalleryDateBrowseMode.all;
  List<_DateBrowseYearEntry> _yearBrowseEntries =
      const <_DateBrowseYearEntry>[];
  List<_DateBrowseMonthEntry> _monthBrowseEntries =
      const <_DateBrowseMonthEntry>[];
  final ScrollController _yearBrowseController = ScrollController();
  final ScrollController _monthBrowseController = ScrollController();
  int? _pendingMonthBrowseScrollIndex;
  int? _pendingMonthBrowseYear;
  DateTime? _pendingMonthBrowseScrollStartedAt;
  int? _selectedYearBrowseAnchor;
  bool _selectedYearAnchorPulseActive = false;
  int? _jumpTargetDataIndex;
  String? _jumpTargetMonthLabel;
  int _jumpTargetMarkerSeed = 0;
  Timer? _jumpTargetHideTimer;
  Timer? _selectedYearAnchorPulseTimer;
  Timer? _scrollbarDateHintHideTimer; // new
  bool _showScrollbarDateHintOverlay = false; // new
  double _lastObservedVerticalScrollOffset = 0; // new
  bool _isSelectionMode = false; // new
  final Set<String> _selectedMediaItemIds = <String>{}; // new
  int _lastHandledClearSelectionSignal = 0; // new
  // #new

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
    _lastHandledClearSelectionSignal = widget.clearSelectionSignal;
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
    _jumpTargetHideTimer?.cancel(); // new
    _jumpTargetHideTimer = null; // new
    _selectedYearAnchorPulseTimer?.cancel(); // new
    _selectedYearAnchorPulseTimer = null; // new
    _scrollbarDateHintHideTimer?.cancel(); // new
    _scrollbarDateHintHideTimer = null; // new
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
    _yearBrowseController.dispose(); // new
    _monthBrowseController.dispose(); // new
    unawaited(widget.source.dispose());
    super.dispose();
  }

  void _disposeRuntime() {
    if (!_isInitialized) return;
    grid.scrollOffset.removeListener(_handleGridScrollOffsetChanged); // new
    if (_isScrollbarFastScrolling) {
      _isScrollbarFastScrolling = false;
      grid.setFastScrollActive(false);
    }
    _hideScrollbarDateHint(notify: false); // new
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
      showStorageIndicator: widget.showStorageIndicator, // new
      storageIndicatorResolver: widget.storageIndicatorResolver, // new
    );
    _gestureController = GridGestureController(
      grid: grid,
      scalingLock: scalingLock,
      onScaleEnd: _handleSnapAfterScale,
      onDebugTripleTouch: grid.debugPrintTable,
    );
    grid.init();
    _lastObservedVerticalScrollOffset = grid.scrollOffset.value.dy; // new
    grid.scrollOffset.addListener(_handleGridScrollOffsetChanged); // new
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
    // Keep original data pipeline intact; date-browse lists are derived only.
    _rebuildDateBrowseEntries(viewItems); // new
    _clearJumpTargetIndicator(notify: false); // new
    _initRuntimeWith(MediaDataSource(viewItems));
    _pruneSelectionAgainstCurrentItems(notify: false); // new
    if (notify) {
      _emitSelectionChanged();
    }
    // #new
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
      final DateTime? left = _resolveSortDate(a); // new
      final DateTime? right = _resolveSortDate(b); // new
      final int byDate = _compareDateDesc(left, right);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });
    return values;
  }

  // new
  List<MediaItem> get _selectedItemsInViewOrder {
    if (!_isInitialized || _selectedMediaItemIds.isEmpty) {
      return const <MediaItem>[];
    }
    return mediaDataSource.items
        .where((item) => _selectedMediaItemIds.contains(item.id))
        .toList(growable: false);
  }

  void _emitSelectionChanged() {
    final ValueChanged<List<MediaItem>>? callback = widget.onSelectionChanged;
    if (callback == null) {
      return;
    }
    callback(_selectedItemsInViewOrder);
  }

  void _pruneSelectionAgainstCurrentItems({bool notify = true}) {
    if (!_isInitialized || _selectedMediaItemIds.isEmpty) {
      if (notify) {
        _emitSelectionChanged();
      }
      return;
    }

    final Set<String> validIds = mediaDataSource.items
        .map((item) => item.id)
        .toSet();
    _selectedMediaItemIds.removeWhere((id) => !validIds.contains(id));
    if (_selectedMediaItemIds.isEmpty) {
      _isSelectionMode = false;
    }
    if (notify) {
      _emitSelectionChanged();
    }
  }

  void _clearSelection({bool notify = true}) {
    final bool hadSelection =
        _isSelectionMode || _selectedMediaItemIds.isNotEmpty;
    if (!hadSelection) {
      if (notify) {
        _emitSelectionChanged();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _selectedMediaItemIds.clear();
        _isSelectionMode = false;
      });
    } else {
      _selectedMediaItemIds.clear();
      _isSelectionMode = false;
    }

    if (notify) {
      _emitSelectionChanged();
    }
  }

  void _toggleSelectionModeFromOverlay() {
    if (!widget.enableMultiSelect) {
      return;
    }
    if (_isSelectionMode || _selectedMediaItemIds.isNotEmpty) {
      _clearSelection();
      return;
    }
    setState(() {
      _isSelectionMode = true;
    });
    _emitSelectionChanged();
  }

  void _toggleSelectionForItem(MediaItem item) {
    if (!widget.enableMultiSelect) {
      return;
    }
    setState(() {
      _isSelectionMode = true;
      if (_selectedMediaItemIds.contains(item.id)) {
        _selectedMediaItemIds.remove(item.id);
      } else {
        _selectedMediaItemIds.add(item.id);
      }
      if (_selectedMediaItemIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
    _emitSelectionChanged();
  }

  bool _isDataIndexSelected(int dataIndex) {
    if (!_isInitialized ||
        dataIndex < 0 ||
        dataIndex >= mediaDataSource.length) {
      return false;
    }
    final MediaItem? item = mediaDataSource.itemAtDataIndex(dataIndex);
    return item != null && _selectedMediaItemIds.contains(item.id);
  }

  void _handleDataIndexLongPress(int dataIndex) {
    if (!widget.enableMultiSelect ||
        !_isInitialized ||
        dataIndex < 0 ||
        dataIndex >= mediaDataSource.length) {
      return;
    }
    final MediaItem? item = mediaDataSource.itemAtDataIndex(dataIndex);
    if (item == null) {
      return;
    }
    _toggleSelectionForItem(item);
  }

  void _handleDataIndexTap(int dataIndex, String? thumbUrl, String heroTag) {
    if (!_isInitialized ||
        dataIndex < 0 ||
        dataIndex >= mediaDataSource.length) {
      return;
    }
    final MediaItem? item = mediaDataSource.itemAtDataIndex(dataIndex);
    if (item == null) {
      return;
    }

    if (widget.enableMultiSelect && _isSelectionMode) {
      _toggleSelectionForItem(item);
      return;
    }

    _openViewerAtDataIndex(
      dataIndex,
      initialHeroTag: heroTag,
      initialThumbUrl: thumbUrl,
    );
  }

  DateTime? _resolveSortDate(MediaItem item) {
    return switch (_sortMode) {
      GallerySortMode.createdAtDesc => item.createdAt ?? item.addedAt,
      GallerySortMode.addedAtDesc => item.addedAt ?? item.createdAt,
    };
  }

  void _rebuildDateBrowseEntries(List<MediaItem> items) {
    final Map<int, _DateBrowseYearBuilder> yearsByKey =
        <int, _DateBrowseYearBuilder>{};
    final Map<int, _DateBrowseMonthBuilder> monthsByKey =
        <int, _DateBrowseMonthBuilder>{};

    for (int index = 0; index < items.length; index++) {
      final MediaItem item = items[index];
      final DateTime? sourceDate = _resolveSortDate(item);
      if (sourceDate == null) {
        // Undated assets stay available in "All" mode only.
        continue;
      }
      final DateTime date = sourceDate.toLocal();
      final int year = date.year;
      final int month = date.month;
      final int monthKey = year * 100 + month;

      final _DateBrowseYearBuilder yearBuilder = yearsByKey.putIfAbsent(
        year,
        () => _DateBrowseYearBuilder(firstDataIndex: index, year: year),
      );
      yearBuilder.totalItemCount += 1;
      if (yearBuilder.previewItems.length < 5) {
        yearBuilder.previewItems.add(item);
      }

      _DateBrowseMonthBuilder? monthBuilder = monthsByKey[monthKey];
      if (monthBuilder == null) {
        monthBuilder = _DateBrowseMonthBuilder(
          firstDataIndex: index,
          year: year,
          month: month,
        );
        monthsByKey[monthKey] = monthBuilder;
        yearBuilder.monthCount += 1;
        if (yearBuilder.firstMonthListIndex < 0) {
          yearBuilder.firstMonthListIndex = monthsByKey.length - 1;
        }
      }
      monthBuilder.totalItemCount += 1;
      if (monthBuilder.previewItems.length < 5) {
        monthBuilder.previewItems.add(item);
      }
    }

    _monthBrowseEntries = monthsByKey.values
        .map(
          (entry) => _DateBrowseMonthEntry(
            year: entry.year,
            month: entry.month,
            firstDataIndex: entry.firstDataIndex,
            totalItemCount: entry.totalItemCount,
            previewItems: List<MediaItem>.unmodifiable(entry.previewItems),
          ),
        )
        .toList(growable: false);

    final Map<int, int> firstMonthIndexByYear = <int, int>{};
    for (int index = 0; index < _monthBrowseEntries.length; index++) {
      firstMonthIndexByYear.putIfAbsent(
        _monthBrowseEntries[index].year,
        () => index,
      );
    }

    _yearBrowseEntries = yearsByKey.values
        .map(
          (entry) => _DateBrowseYearEntry(
            year: entry.year,
            firstDataIndex: entry.firstDataIndex,
            firstMonthListIndex:
                firstMonthIndexByYear[entry.year] ?? entry.firstMonthListIndex,
            monthCount: entry.monthCount,
            totalItemCount: entry.totalItemCount,
            previewItems: List<MediaItem>.unmodifiable(entry.previewItems),
          ),
        )
        .toList(growable: false);

    // Keep selected-year anchor stable by year key; clear only when missing.
    if (_selectedYearBrowseAnchor != null &&
        !_yearBrowseEntries.any(
          (entry) => entry.year == _selectedYearBrowseAnchor,
        )) {
      _selectedYearAnchorPulseTimer?.cancel();
      _selectedYearAnchorPulseTimer = null;
      _selectedYearBrowseAnchor = null;
      _selectedYearAnchorPulseActive = false;
    }
  }
  // #new

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

  // new
  void _setDateBrowseMode(GalleryDateBrowseMode mode) {
    if (!widget.showDateBrowseOverlay || _dateBrowseMode == mode) {
      return;
    }
    if (mode != GalleryDateBrowseMode.all) {
      _clearJumpTargetIndicator(notify: false);
      _hideScrollbarDateHint(notify: false); // new
    } // new
    setState(() {
      _dateBrowseMode = mode;
      if (mode != GalleryDateBrowseMode.month) {
        _clearPendingMonthBrowseScroll();
      }
      if (mode == GalleryDateBrowseMode.all) {
        _selectedYearBrowseAnchor = null;
        _selectedYearAnchorPulseActive = false;
        _selectedYearAnchorPulseTimer?.cancel();
        _selectedYearAnchorPulseTimer = null;
      }
    });
    if (mode == GalleryDateBrowseMode.month) {
      _scheduleMonthBrowseScroll();
    } else if (mode == GalleryDateBrowseMode.year) {
      _scheduleYearBrowseScrollToTop();
    }
  }

  void _handleYearBrowseRowTap(_DateBrowseYearEntry entry) {
    if (!widget.showDateBrowseOverlay) {
      return;
    }
    _clearJumpTargetIndicator(notify: false); // new
    _hideScrollbarDateHint(notify: false); // new
    setState(() {
      _dateBrowseMode = GalleryDateBrowseMode.month;
      _pendingMonthBrowseYear = entry.year;
      _pendingMonthBrowseScrollIndex = entry.firstMonthListIndex < 0
          ? null
          : entry.firstMonthListIndex;
      _pendingMonthBrowseScrollStartedAt = DateTime.now();
      _selectedYearBrowseAnchor = entry.year;
      _selectedYearAnchorPulseActive = true;
    });
    _scheduleMonthBrowseScroll();
    _scheduleSelectedYearAnchorPulseHide();
  }

  void _handleMonthBrowseRowTap(_DateBrowseMonthEntry entry) {
    if (!widget.showDateBrowseOverlay) {
      return;
    }
    _hideScrollbarDateHint(notify: false); // new
    _clearPendingMonthBrowseScroll();
    final String monthLabel = _formatMonthBrowseLabel(context, entry);
    _jumpTargetHideTimer?.cancel();
    setState(() {
      _dateBrowseMode = GalleryDateBrowseMode.all;
      _jumpTargetDataIndex = entry.firstDataIndex;
      _jumpTargetMonthLabel = monthLabel;
      _jumpTargetMarkerSeed += 1;
      _selectedYearBrowseAnchor = null;
      _selectedYearAnchorPulseActive = false;
    });
    _selectedYearAnchorPulseTimer?.cancel();
    _selectedYearAnchorPulseTimer = null;
    _scheduleJumpTargetIndicatorHide();
    _jumpToDataIndex(entry.firstDataIndex);
  }

  void _scheduleJumpTargetIndicatorHide() {
    _jumpTargetHideTimer = Timer(_jumpTargetIndicatorDuration, () {
      if (!mounted) {
        return;
      }
      _clearJumpTargetIndicator();
    });
  }

  void _clearJumpTargetIndicator({bool notify = true}) {
    _jumpTargetHideTimer?.cancel();
    _jumpTargetHideTimer = null;
    final bool hasIndicator =
        _jumpTargetDataIndex != null || _jumpTargetMonthLabel != null;
    if (!hasIndicator) {
      return;
    }
    if (notify && mounted) {
      setState(() {
        _jumpTargetDataIndex = null;
        _jumpTargetMonthLabel = null;
      });
    } else {
      _jumpTargetDataIndex = null;
      _jumpTargetMonthLabel = null;
    }
  }

  void _scheduleSelectedYearAnchorPulseHide() {
    _selectedYearAnchorPulseTimer?.cancel();
    _selectedYearAnchorPulseTimer = Timer(_selectedYearAnchorPulseDuration, () {
      if (!mounted) {
        return;
      }
      if (!_selectedYearAnchorPulseActive &&
          _selectedYearBrowseAnchor == null) {
        return;
      }
      setState(() {
        _selectedYearAnchorPulseActive = false;
        _selectedYearBrowseAnchor = null;
      });
    });
  }

  void _scheduleYearBrowseScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dateBrowseMode != GalleryDateBrowseMode.year) {
        return;
      }
      if (_yearBrowseEntries.isEmpty) {
        return;
      }
      if (!_yearBrowseController.hasClients) {
        _scheduleYearBrowseScrollToTop();
        return;
      }
      final ScrollPosition position = _yearBrowseController.position;
      if (position.pixels.abs() <= _pendingMonthBrowseTopTolerance) {
        return;
      }
      _yearBrowseController.jumpTo(0);
    });
  }

  void _scheduleMonthBrowseScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _applyPendingMonthBrowseScroll();
    });
  }

  void _clearPendingMonthBrowseScroll() {
    _pendingMonthBrowseScrollIndex = null;
    _pendingMonthBrowseYear = null;
    _pendingMonthBrowseScrollStartedAt = null;
  }

  bool _isPendingMonthBrowseScrollExpired() {
    final DateTime? startedAt = _pendingMonthBrowseScrollStartedAt;
    if (startedAt == null) {
      return false;
    }
    return DateTime.now().difference(startedAt) >=
        _pendingMonthBrowseScrollTimeout;
  }

  void _applyPendingMonthBrowseScroll() {
    if (_dateBrowseMode != GalleryDateBrowseMode.month) {
      _clearPendingMonthBrowseScroll();
      return;
    }
    if (_pendingMonthBrowseYear == null &&
        _pendingMonthBrowseScrollIndex == null) {
      return;
    }
    final int? resolvedIndex = _resolvePendingMonthBrowseScrollIndex();
    if (resolvedIndex == null || resolvedIndex < 0) {
      if (_isPendingMonthBrowseScrollExpired()) {
        _clearPendingMonthBrowseScroll();
        return;
      }
      _scheduleMonthBrowseScroll();
      return;
    }
    if (!_monthBrowseController.hasClients) {
      if (_isPendingMonthBrowseScrollExpired()) {
        _clearPendingMonthBrowseScroll();
        return;
      }
      _scheduleMonthBrowseScroll();
      return;
    }
    // Old behavior:
    // _pendingMonthBrowseScrollIndex = null;
    // _pendingMonthBrowseYear = null;
    // Keep pending target until the row is actually visible in viewport.
    const double rowExtent = _dateBrowseRowHeight + _dateBrowseRowSpacing;
    final ScrollPosition position = _monthBrowseController.position;
    final double rowStartOffset = resolvedIndex * rowExtent;
    final double targetOffset = rowStartOffset.clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((position.pixels - targetOffset).abs() >
        _pendingMonthBrowseTopTolerance) {
      // smooth behavior:
      // unawaited(
      //   _monthBrowseController.animateTo(
      //     targetOffset,
      //     duration: const Duration(milliseconds: 260),
      //     curve: Curves.easeOutCubic,
      //   ),
      // );
      _monthBrowseController.jumpTo(targetOffset);
    }

    final double currentPixels = _monthBrowseController.position.pixels;
    final bool alignedAtTop =
        (currentPixels - rowStartOffset).abs() <=
        _pendingMonthBrowseTopTolerance;
    if (alignedAtTop) {
      _clearPendingMonthBrowseScroll();
      return;
    }

    if (_isPendingMonthBrowseScrollExpired()) {
      _clearPendingMonthBrowseScroll();
      return;
    }

    _scheduleMonthBrowseScroll();
  }

  int? _resolvePendingMonthBrowseScrollIndex() {
    final int? pendingYear = _pendingMonthBrowseYear;
    if (pendingYear != null) {
      final int resolvedByYear = _monthBrowseEntries.indexWhere(
        (entry) => entry.year == pendingYear,
      );
      if (resolvedByYear >= 0) {
        return resolvedByYear;
      }
      return null;
    }
    return _pendingMonthBrowseScrollIndex;
  }

  void _jumpToDataIndex(int dataIndex) {
    if (!_isInitialized ||
        dataIndex < 0 ||
        dataIndex >= mediaDataSource.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isInitialized) {
        return;
      }
      final int cols = grid.currentColCount <= 0 ? 1 : grid.currentColCount;
      grid.updateViewportFirstCol();
      final int maxFirstCol = math.max(0, grid.defaultColCount - cols);
      final int leftCol = grid.viewportFirstCol.clamp(0, maxFirstCol);
      final int firstCol = grid.firstCellCol.clamp(0, grid.defaultColCount);
      final int leadingSlots = (firstCol - leftCol).clamp(0, cols - 1).toInt();
      final int targetRealRow = (leadingSlots + dataIndex) ~/ cols;
      grid.jumpToRealTopRow(
        targetRealRow.toDouble(),
        colCount: cols,
        leftCol: leftCol,
      );
    });
  }

  ({int row, int col})? _resolveCellPositionForDataIndex(int dataIndex) {
    final int cols = grid.targetColCount <= 0 ? 1 : grid.targetColCount;
    if (cols <= 0 || cols >= grid.baseCells.length) {
      return null;
    }
    final int baseCell = grid.baseCells[cols];
    final int adjusted = dataIndex + baseCell;
    final int logicalRow = (adjusted / cols).floor();
    int col = adjusted % cols;
    if (col < 0) {
      col += cols;
    }
    final int row = logicalRow - grid.baseRow;
    if (row < 0 || col < 0 || col >= grid.defaultColCount) {
      return null;
    }
    return (row: row, col: col);
  }

  Widget _withJumpTargetMarker({
    required Widget child,
    required GridAppearancePalette palette,
  }) {
    final int? dataIndex = _jumpTargetDataIndex;
    if (dataIndex == null || _dateBrowseMode != GalleryDateBrowseMode.all) {
      return child;
    }
    if (!grid.isDataIndexInViewport(dataIndex, rowEpsilon: 0.6)) {
      return child;
    }
    final ({int row, int col})? markerPosition =
        _resolveCellPositionForDataIndex(dataIndex);
    if (markerPosition == null) {
      return child;
    }
    final bool isDark = palette.brightness == Brightness.dark;
    final Color accent = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          left: markerPosition.col * grid.cellSize,
          top: markerPosition.row * grid.cellSize,
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey<int>(_jumpTargetMarkerSeed),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 1.14, end: 1.0),
              builder: (context, scale, _) {
                return Transform.scale(
                  scale: scale,
                  child: SizedBox(
                    width: grid.cellSize,
                    height: grid.cellSize,
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: accent.withValues(alpha: 0.92),
                            width: 2.2,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: accent.withValues(alpha: 0.34),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.popupMenuBackground.withValues(
                                  alpha: isDark ? 0.9 : 0.96,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.7),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(
                                  Icons.my_location_rounded,
                                  size: 10,
                                  color: accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
  // #new

  Future<void> _openViewerAtDataIndex(
    int dataIndex, {
    required String initialHeroTag,
    String? initialThumbUrl, // new
  }) async {
    if (!_isInitialized) return;
    if (dataIndex < 0 || dataIndex >= mediaDataSource.length) return;
    final MediaItem? item = mediaDataSource.itemAtDataIndex(dataIndex);
    // new
    final Uint8List? initialThumbBytes = _resolveInitialHandoffThumbBytes(
      item: item,
      initialThumbUrl: initialThumbUrl,
    );
    bool initialOriginalReady = false;
    _warmupOriginalForViewerOpen(dataIndex: dataIndex);

    // final MediaItem? item = mediaDataSource.itemAtDataIndex(dataIndex);
    // if (item != null && !item.isVideo && _isNetworkUrl(item.originalUrl)) {
    //   final int decodeWidth = _viewerDecodeWidthForItem(item);
    //   final int? decodeHeight = _viewerDecodeHeightForItem(item, decodeWidth);
    //   final ImageProvider<Object> provider = ViewerCacheManager.providerFor(
    //     item.originalUrl,
    //     maxWidth: decodeWidth,
    //     maxHeight: decodeHeight,
    //     debugIndex: dataIndex,
    //   );
    //   final ImageCacheStatus? cacheStatus = await provider.obtainCacheStatus(
    //     configuration: createLocalImageConfiguration(context),
    //   );
    //   final bool inMemoryCache = cacheStatus?.tracked ?? false;
    //   final bool inDiskCache =
    //       await ViewerCacheManager.instance.isCachedOnDisk(
    //         item.originalUrl,
    //         maxWidth: decodeWidth,
    //         maxHeight: decodeHeight,
    //       );
    //   if (!mounted) return;
    //   if (inMemoryCache || inDiskCache) {
    //     try {
    //       await precacheImage(provider, context);
    //       initialOriginalReady = true;
    //     } catch (_) {
    //       initialOriginalReady = inMemoryCache;
    //     }
    //     if (!mounted) return;
    //   }
    // }
    // #new
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
          initialThumbUrl: initialThumbUrl, // new
          initialThumbBytes: initialThumbBytes, // new
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

  Uint8List? _resolveInitialHandoffThumbBytes({
    required MediaItem? item,
    required String? initialThumbUrl,
  }) {
    final String source = initialThumbUrl?.trim() ?? '';
    if (item == null || source.isEmpty) {
      return null;
    }

    // Remote grid cache keys use thumb URL directly.
    if (!item.isLocal) {
      final Uint8List? remoteBytes = _bytesCache.peek(source);
      if (remoteBytes != null && remoteBytes.isNotEmpty) {
        return remoteBytes;
      }
      return null;
    }

    // Local grid cache keys are typed to avoid image/video key collisions.
    final String typedKey = LocalDeviceMediaUri.buildTypedThumbCacheKey(
      source,
      isVideo: item.isVideo,
    );
    final Uint8List? localBytes = _bytesCache.peek(typedKey);
    if (localBytes != null && localBytes.isNotEmpty) {
      return localBytes;
    }
    return null;
  }

  void _warmupOriginalForViewerOpen({required int dataIndex}) {
    final MediaItem? item = mediaDataSource.itemAtDataIndex(dataIndex);
    if (item == null || item.isVideo || !_isNetworkUrl(item.originalUrl)) {
      return;
    }
    final int decodeWidth = _viewerDecodeWidthForItem(item);
    final int? decodeHeight = _viewerDecodeHeightForItem(item, decodeWidth);
    final ImageProvider<Object> provider = ViewerCacheManager.providerFor(
      item.originalUrl,
      maxWidth: decodeWidth,
      maxHeight: decodeHeight,
      debugIndex: dataIndex,
    );
    // Non-blocking warmup to keep tap-to-open instant.
    unawaited(
      (() async {
        final ImageCacheStatus? cacheStatus = await provider.obtainCacheStatus(
          configuration: createLocalImageConfiguration(context),
        );
        final bool inMemoryCache = cacheStatus?.tracked ?? false;
        final bool inDiskCache = await ViewerCacheManager.instance
            .isCachedOnDisk(
              item.originalUrl,
              maxWidth: decodeWidth,
              maxHeight: decodeHeight,
            );
        if (!mounted || (!inMemoryCache && !inDiskCache)) {
          return;
        }
        try {
          await precacheImage(provider, context);
        } catch (_) {
          // Best-effort warmup only.
        }
      })(),
    );
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

  // new
  Widget _buildSelectModeButton(GridAppearancePalette palette) {
    final bool isActive = _isSelectionMode || _selectedMediaItemIds.isNotEmpty;
    final int selectedCount = _selectedMediaItemIds.length;
    final String label = isActive
        ? (selectedCount > 0 ? 'Selected $selectedCount' : 'Cancel')
        : 'Select';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.menuButtonBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x66FFFFFF), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _toggleSelectionModeFromOverlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isActive ? Icons.close_rounded : Icons.checklist_rounded,
                  size: 16,
                  color: palette.menuButtonIcon,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: palette.menuButtonIcon,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  // #new

  Widget _buildSortFilterMenuButton() {
    final double bottomOffset = widget.showDateBrowseOverlay ? 72 : 14; // new
    return Positioned(
      // new
      // top: 8,
      // right: 8,
      right: 20,
      bottom: bottomOffset, // new
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

  // new
  Widget _buildDateBrowseModeButton() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 14,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GalleryDateBrowseOverlay(
          mode: _dateBrowseMode,
          texts: widget.dateBrowseTexts,
          onModeChanged: _setDateBrowseMode,
        ),
      ),
    );
  }

  Widget _buildDateBrowsePanel(GridAppearancePalette palette) {
    if (_dateBrowseMode == GalleryDateBrowseMode.all) {
      return const SizedBox.shrink();
    }
    final _DateBrowseColorScheme colors = _DateBrowseColorScheme.fromPalette(
      palette,
    );

    final bool showYearList = _dateBrowseMode == GalleryDateBrowseMode.year;
    final int? selectedYearAnchor = _selectedYearBrowseAnchor;
    final int? selectedYearFirstMonthListIndex = selectedYearAnchor == null
        ? null
        : _monthBrowseEntries.indexWhere(
            (entry) => entry.year == selectedYearAnchor,
          );
    final List<_DateBrowseRowData> rows = showYearList
        ? _yearBrowseEntries
              .map(
                (entry) => _DateBrowseRowData(
                  kind: _DateBrowseRowKind.year,
                  key: 'year_${entry.year}',
                  label: entry.year.toString(),
                  year: entry.year,
                  primaryStat: entry.monthCount,
                  secondaryStat: entry.totalItemCount,
                  previewItems: entry.previewItems,
                  onTap: () => _handleYearBrowseRowTap(entry),
                ),
              )
              .toList(growable: false)
        : _monthBrowseEntries
              .asMap()
              .entries
              .map((entryWithIndex) {
                final int listIndex = entryWithIndex.key;
                final _DateBrowseMonthEntry entry = entryWithIndex.value;
                return _DateBrowseRowData(
                  kind: _DateBrowseRowKind.month,
                  key: 'month_${entry.year}_${entry.month}',
                  label: _formatMonthBrowseLabel(context, entry),
                  year: entry.year,
                  month: entry.month,
                  isSelectedYearAnchor:
                      selectedYearFirstMonthListIndex != null &&
                      selectedYearFirstMonthListIndex >= 0 &&
                      listIndex == selectedYearFirstMonthListIndex,
                  primaryStat: entry.totalItemCount,
                  previewItems: entry.previewItems,
                  onTap: () => _handleMonthBrowseRowTap(entry),
                );
              })
              .toList(growable: false);

    final ScrollController controller = showYearList
        ? _yearBrowseController
        : _monthBrowseController;

    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.panelGradientStart, colors.panelGradientEnd],
          ),
        ),
        child: Column(
          children: <Widget>[
            _buildDateBrowsePanelHeader(
              colors: colors,
              rowCount: rows.length,
              showYearList: showYearList,
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No data for the current filter'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final double viewportHeight = constraints.maxHeight;
                        final double topAlignBottomPadding = showYearList
                            ? _dateBrowseListBaseBottomPadding
                            : math.max(
                                _dateBrowseListBaseBottomPadding,
                                math.max(
                                  0,
                                  viewportHeight.isFinite
                                      ? viewportHeight -
                                            _dateBrowseRowHeight +
                                            _dateBrowseTopAlignPaddingSlack
                                      : 0,
                                ),
                              );
                        return ListView.separated(
                          controller: controller,
                          // padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
                          padding: EdgeInsets.fromLTRB(
                            0,
                            0,
                            0,
                            topAlignBottomPadding,
                          ),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: _dateBrowseRowSpacing),
                          itemBuilder: (context, index) {
                            final _DateBrowseRowData row = rows[index];
                            return _buildDateBrowseRow(
                              row: row,
                              colors: colors,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // new
  Widget _buildJumpTargetHintChip(GridAppearancePalette palette) {
    final int? dataIndex = _jumpTargetDataIndex;
    final String? monthLabel = _jumpTargetMonthLabel;
    if (dataIndex == null ||
        monthLabel == null ||
        _dateBrowseMode != GalleryDateBrowseMode.all) {
      return const SizedBox.shrink();
    }
    final bool isDark = palette.brightness == Brightness.dark;
    final Color accent = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);
    final double topOffset = widget.showDateOverlay ? 40 : 10;
    return Positioned(
      top: topOffset,
      left: 12,
      right: 12,
      child: Align(
        alignment: Alignment.topCenter,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.popupMenuBackground.withValues(
                alpha: isDark ? 0.9 : 0.95,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.42)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.my_location_rounded, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    monthLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.popupMenuItemText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _buildScrollbarMonthYearLabel(MediaItem item) {
    final DateTime? sourceDate = _resolveSortDate(item);
    if (sourceDate == null) {
      return null;
    }
    final DateTime date = sourceDate.toLocal();
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    return localizations.formatMonthYear(DateTime(date.year, date.month));
  }

  bool _shouldShowScrollbarDateHint({required bool scaling}) {
    if (!widget.showScrollbarDateHint) {
      return false;
    }
    if (scaling) {
      return false;
    }
    if (_dateBrowseMode != GalleryDateBrowseMode.all) {
      return false;
    }
    return _showScrollbarDateHintOverlay || _isScrollbarFastScrolling;
  }

  void _handleGridScrollOffsetChanged() {
    if (!_isInitialized || !widget.showScrollbarDateHint) {
      return;
    }
    final double currentOffset = grid.scrollOffset.value.dy;
    final double delta = currentOffset - _lastObservedVerticalScrollOffset;
    _lastObservedVerticalScrollOffset = currentOffset;
    if (delta.abs() < 0.01) {
      return;
    }
    if (_dateBrowseMode != GalleryDateBrowseMode.all) {
      _hideScrollbarDateHint();
      return;
    }
    _markScrollbarDateHintInteraction();
  }

  void _markScrollbarDateHintInteraction() {
    if (!widget.showScrollbarDateHint) {
      return;
    }
    if (_dateBrowseMode != GalleryDateBrowseMode.all) {
      return;
    }
    if (!_showScrollbarDateHintOverlay) {
      if (!mounted) {
        _showScrollbarDateHintOverlay = true;
      } else {
        setState(() {
          _showScrollbarDateHintOverlay = true;
        });
      }
    }
    _scheduleScrollbarDateHintHide();
  }

  void _scheduleScrollbarDateHintHide() {
    _scrollbarDateHintHideTimer?.cancel();
    _scrollbarDateHintHideTimer = Timer(_scrollbarDateHintHideDelay, () {
      if (!mounted) {
        return;
      }
      if (_isScrollbarFastScrolling) {
        return;
      }
      if (!_showScrollbarDateHintOverlay) {
        return;
      }
      setState(() {
        _showScrollbarDateHintOverlay = false;
      });
    });
  }

  void _hideScrollbarDateHint({bool notify = true}) {
    _scrollbarDateHintHideTimer?.cancel();
    _scrollbarDateHintHideTimer = null;
    if (!_showScrollbarDateHintOverlay) {
      return;
    }
    if (notify && mounted) {
      setState(() {
        _showScrollbarDateHintOverlay = false;
      });
    } else {
      _showScrollbarDateHintOverlay = false;
    }
  }

  Widget? _buildScrollbarDateHintOverlay({
    required bool scaling,
    required RealDataScrollbarOverlayMetrics metrics,
  }) {
    if (!_shouldShowScrollbarDateHint(scaling: scaling)) {
      return null;
    }
    if (!metrics.canScroll) {
      return null;
    }
    final double maxTop = math.max(
      0,
      metrics.trackExtent - _scrollbarDateHintBubbleHeight,
    );
    final double overlayTop =
        (metrics.thumbCenterY - (_scrollbarDateHintBubbleHeight / 2))
            .clamp(0.0, maxTop)
            .toDouble();
    return Positioned(
      top: overlayTop,
      right: metrics.width + _scrollbarDateHintBubbleGap,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: GridDateOverlay(
            grid: grid,
            mediaDataSource: mediaDataSource,
            textBuilder: _buildScrollbarMonthYearLabel,
            preferAddedAt: _sortMode == GallerySortMode.addedAtDesc,
          ),
        ),
      ),
    );
  }
  // #new

  Widget _buildDateBrowsePanelHeader({
    required _DateBrowseColorScheme colors,
    required int rowCount,
    required bool showYearList,
  }) {
    final String title = showYearList
        ? widget.dateBrowseTexts.optionYear
        : widget.dateBrowseTexts.optionMonth;
    // Old hint text (not rendered):
    // final String hint = showYearList
    //     ? '${widget.dateBrowseTexts.optionYear} -> ${widget.dateBrowseTexts.optionMonth}'
    //     : '${widget.dateBrowseTexts.optionMonth} -> ${widget.dateBrowseTexts.optionAll}';
    final IconData icon = showYearList
        ? Icons.calendar_today_rounded
        : Icons.calendar_month_rounded;
    // final int? selectedYearAnchor = showYearList
    //     ? null
    //     : _selectedYearBrowseAnchor; // new

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.headerBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.headerBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.headerIconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    icon,
                    size: 16,
                    color: colors.headerIconForeground,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '$title ($rowCount)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.headerTitle,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // if (selectedYearAnchor != null) ...<Widget>[
              //   const SizedBox(width: 8),
              //   DecoratedBox(
              //     decoration: BoxDecoration(
              //       color: colors.yearAccent.withValues(alpha: 0.16),
              //       borderRadius: BorderRadius.circular(999),
              //       border: Border.all(
              //         color: colors.yearAccent.withValues(alpha: 0.42),
              //       ),
              //     ),
              //     child: Padding(
              //       padding: const EdgeInsets.symmetric(
              //         horizontal: 8,
              //         vertical: 5,
              //       ),
              //       child: Row(
              //         mainAxisSize: MainAxisSize.min,
              //         children: <Widget>[
              //           Icon(
              //             Icons.my_location_rounded,
              //             size: 11,
              //             color: colors.yearAccent,
              //           ),
              //           const SizedBox(width: 4),
              //           Text(
              //             '${widget.dateBrowseTexts.optionYear}: $selectedYearAnchor',
              //             style: TextStyle(
              //               color: colors.primaryText,
              //               fontSize: 11,
              //               fontWeight: FontWeight.w700,
              //               height: 1.0,
              //             ),
              //           ),
              //         ],
              //       ),
              //     ),
              //   ),
              // ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatMonthBrowseLabel(
    BuildContext context,
    _DateBrowseMonthEntry entry,
  ) {
    final Locale locale = Localizations.localeOf(context);
    final String language = locale.languageCode.toLowerCase();
    if (language == 'vi') {
      return 'Tháng ${entry.month} ${entry.year}';
    }
    if (language == 'en') {
      const List<String> monthNames = <String>[
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final int monthIndex = (entry.month - 1).clamp(0, monthNames.length - 1);
      return '${monthNames[monthIndex]} ${entry.year}';
    }
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    return localizations.formatMonthYear(DateTime(entry.year, entry.month));
  }

  Widget _buildDateBrowseRow({
    required _DateBrowseRowData row,
    required _DateBrowseColorScheme colors,
  }) {
    final bool isYearRow = row.kind == _DateBrowseRowKind.year;
    final bool isSelectedYearAnchorRow =
        !isYearRow &&
        row.isSelectedYearAnchor &&
        _selectedYearBrowseAnchor != null;
    final bool showSelectedYearAnchorPulse =
        isSelectedYearAnchorRow && _selectedYearAnchorPulseActive;
    final Color accentColor = isYearRow
        ? colors.yearAccent
        : colors.monthAccent;
    // final String kindLabel = isYearRow
    //     ? widget.dateBrowseTexts.optionYear
    //     : widget.dateBrowseTexts.optionMonth;

    return SizedBox(
      height: _dateBrowseRowHeight,
      child: Material(
        color: Colors.transparent,
        // borderRadius: BorderRadius.circular(14),
        child: InkWell(
          // borderRadius: BorderRadius.circular(14),
          onTap: row.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            // decoration: BoxDecoration(
            //   color: isSelectedYearAnchorRow
            //       ? accentColor.withValues(
            //           alpha: showSelectedYearAnchorPulse ? 0.18 : 0.1,
            //         )
            //       : Colors.transparent,
            //   // border: Border(
            //   //   left: BorderSide(
            //   //     color: isSelectedYearAnchorRow
            //   //         ? accentColor.withValues(
            //   //             alpha: showSelectedYearAnchorPulse ? 0.98 : 0.74,
            //   //           )
            //   //         : Colors.transparent,
            //   //     width: isSelectedYearAnchorRow ? 3 : 0,
            //   //   ),
            //   // ),
            // ),
            child: Padding(
              // padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          isYearRow
                              ? Icons.calendar_today_rounded
                              : Icons.calendar_month_rounded,
                          size: 14,
                          color: accentColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    row.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.primaryText,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildDateBrowseStatChip(
                                icon: isYearRow
                                    ? Icons.view_module_rounded
                                    : Icons.photo_library_outlined,
                                value: row.primaryStat,
                                colors: colors,
                              ),
                              if (row.secondaryStat != null) ...<Widget>[
                                const SizedBox(width: 6),
                                _buildDateBrowseStatChip(
                                  icon: Icons.photo_rounded,
                                  value: row.secondaryStat!,
                                  colors: colors,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isSelectedYearAnchorRow) ...<Widget>[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.my_location_rounded,
                            size: 12,
                            color: accentColor.withValues(
                              alpha: showSelectedYearAnchorPulse ? 1 : 0.9,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final int previewCount = row.previewItems.length
                                  .clamp(0, 5)
                                  .toInt();
                              // child: Row(
                              //   children: List<Widget>.generate(5, (previewIndex) {
                              //     final MediaItem? item =
                              //         previewIndex < row.previewItems.length
                              //         ? row.previewItems[previewIndex]
                              //         : null;
                              //     return Expanded(
                              //       child: _buildDateBrowsePreviewTile(
                              //         rowKey: row.key,
                              //         previewIndex: previewIndex,
                              //         item: item,
                              //         colors: colors,
                              //       ),
                              //     );
                              //   }),
                              // ),
                              if (previewCount <= 0) {
                                return const SizedBox.shrink();
                              }
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final double maxWidth = constraints.maxWidth;
                                  if (maxWidth <= 0 || !maxWidth.isFinite) {
                                    return const SizedBox.shrink();
                                  }
                                  final double tileWidth = maxWidth / 5;
                                  return Row(
                                    children: List<Widget>.generate(
                                      previewCount,
                                      (previewIndex) {
                                        final MediaItem item =
                                            row.previewItems[previewIndex];
                                        return SizedBox(
                                          width: tileWidth,
                                          child: _buildDateBrowsePreviewTile(
                                            rowKey: row.key,
                                            previewIndex: previewIndex,
                                            item: item,
                                            colors: colors,
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.chevron,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateBrowseStatChip({
    required IconData icon,
    required int value,
    required _DateBrowseColorScheme colors,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 11,
              color: colors.chipForeground.withValues(alpha: 0.92),
            ),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: TextStyle(
                color: colors.chipForeground,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateBrowsePreviewTile({
    required String rowKey,
    required int previewIndex,
    required MediaItem? item,
    required _DateBrowseColorScheme colors,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: ColoredBox(
        color: colors.previewPlaceholder,
        child: item == null
            ? const SizedBox.expand()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final double side = constraints.biggest.shortestSide;
                  if (side <= 0 || !side.isFinite) {
                    return const SizedBox.shrink();
                  }
                  final CellData data = CellData(
                    id: 'browse_${rowKey}_$previewIndex',
                    text: '',
                    mediaItem: item,
                    thumbEdge: 100,
                    thumbUrl: item.pickGridThumbForEdge(100),
                    renderScale: 1.0,
                    currentColCount: 5,
                    targetColCount: 5,
                    preferTargetColCount: false,
                  );
                  return GridCell(
                    data: data,
                    size: side,
                    bytesCache: _bytesCache,
                  );
                },
              ),
      ),
    );
  }
  // #new

  @override
  void didUpdateWidget(covariant PizGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableReuseCell && !widget.enableReuseCell) {
      _cellPool.clear();
    }
    // new
    if (oldWidget.enableMultiSelect && !widget.enableMultiSelect) {
      _clearSelection(notify: true);
    }
    if (oldWidget.clearSelectionSignal != widget.clearSelectionSignal &&
        _lastHandledClearSelectionSignal != widget.clearSelectionSignal) {
      _lastHandledClearSelectionSignal = widget.clearSelectionSignal;
      _clearSelection(notify: true);
    }

    if (_isInitialized &&
        (oldWidget.showStorageIndicator != widget.showStorageIndicator ||
            oldWidget.storageIndicatorResolver !=
                widget.storageIndicatorResolver)) {
      _visibleCellsBuilder = GridVisibleCellsBuilder(
        grid: grid,
        mediaDataSource: mediaDataSource,
        cellPool: _cellPool,
        showDebugOutOfRangeCells: _showDebugOutOfRangeCells,
        bytesCache: _bytesCache,
        showStorageIndicator: widget.showStorageIndicator,
        storageIndicatorResolver: widget.storageIndicatorResolver,
      );
      _cellPool.clear();
      // storage indicator wasn't wired into the new grid.
      setState(() {});
    }
    // #new
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
    if (oldWidget.showScrollbarDateHint && !widget.showScrollbarDateHint) {
      _hideScrollbarDateHint();
    } // new
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
    if (widget.showScrollbarDateHint) {
      if (isDragging) {
        _markScrollbarDateHintInteraction();
      } else {
        _scheduleScrollbarDateHintHide();
      }
    } // new
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
    // new
    // final GridAppearancePalette palette = GridAppearancePalette.of(context);
    final Brightness currentAppBrightness = Theme.of(context).brightness;
    final GridAppearancePalette palette = GridAppearancePalette.of(
      context,
      mode: currentAppBrightness == Brightness.dark
          ? GridAppearanceMode.dark
          : GridAppearanceMode.light,
    );
    // #new
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
                                            // new
                                            // return _visibleCellsBuilder.buildVisibleCells(...);
                                            final Widget
                                            visibleCells = _visibleCellsBuilder
                                                .buildVisibleCells(
                                                  window: liveWindow,
                                                  enableReuseCell:
                                                      widget.enableReuseCell,
                                                  lightweightMode: false,
                                                  thumbEdgeOverride: null,
                                                  onDataIndexTap:
                                                      _handleDataIndexTap, // new
                                                  onDataIndexLongPress:
                                                      _handleDataIndexLongPress, // new
                                                  isDataIndexSelected:
                                                      _isDataIndexSelected, // new
                                                );
                                            return _withJumpTargetMarker(
                                              child: visibleCells,
                                              palette: palette,
                                            );
                                            // #new
                                          }
                                          // new
                                          final Widget fastCells = Stack(
                                            children: [
                                              _visibleCellsBuilder.buildVisibleCells(
                                                window: liveWindow,
                                                enableReuseCell:
                                                    widget.enableReuseCell,
                                                lightweightMode: true,
                                                thumbEdgeOverride: null,
                                                onDataIndexTap:
                                                    _handleDataIndexTap, // new
                                                onDataIndexLongPress:
                                                    _handleDataIndexLongPress, // new
                                                isDataIndexSelected:
                                                    _isDataIndexSelected, // new
                                              ),
                                              _visibleCellsBuilder.buildVisibleCells(
                                                window: renderWindow,
                                                enableReuseCell:
                                                    widget.enableReuseCell,
                                                lightweightMode: false,
                                                thumbEdgeOverride:
                                                    _fastScrollThumbEdge,
                                                onDataIndexTap:
                                                    _handleDataIndexTap, // new
                                                onDataIndexLongPress:
                                                    _handleDataIndexLongPress, // new
                                                isDataIndexSelected:
                                                    _isDataIndexSelected, // new
                                              ),
                                            ],
                                          );
                                          return _withJumpTargetMarker(
                                            child: fastCells,
                                            palette: palette,
                                          );
                                          // #new
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
                      overlayBuilder: (context, metrics) =>
                          _buildScrollbarDateHintOverlay(
                            scaling: scaling,
                            metrics: metrics,
                          ), // new
                    ),
                  ),
                  if (_showFpsOverlay)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: FpsBadge(monitor: _fpsMonitor),
                    ),
                  // new
                  if ((widget.showDateOverlay &&
                          _dateBrowseMode == GalleryDateBrowseMode.all) ||
                      (widget.enableMultiSelect &&
                          widget.showSelectModeButton)) // new
                    Positioned(
                      top: 8,
                      left: _showFpsOverlay ? 96 : 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (widget.showDateOverlay &&
                              _dateBrowseMode == GalleryDateBrowseMode.all)
                            GridDateOverlay(
                              grid: grid,
                              mediaDataSource: mediaDataSource,
                              textBuilder: widget.dateOverlayTextBuilder,
                              preferAddedAt:
                                  _sortMode == GallerySortMode.addedAtDesc,
                            ),
                          if (widget.showDateOverlay &&
                              _dateBrowseMode == GalleryDateBrowseMode.all &&
                              widget.enableMultiSelect &&
                              widget.showSelectModeButton)
                            const SizedBox(width: 8),
                          if (widget.enableMultiSelect &&
                              widget.showSelectModeButton)
                            _buildSelectModeButton(palette),
                        ], // #new
                      ),
                    ),
                  _buildJumpTargetHintChip(palette), // new
                  if (widget.showDateBrowseOverlay)
                    _buildDateBrowsePanel(palette), // new
                  if (widget.showDateBrowseOverlay)
                    _buildDateBrowseModeButton(), // new
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

@immutable
class _DateBrowseColorScheme {
  const _DateBrowseColorScheme({
    required this.panelGradientStart,
    required this.panelGradientEnd,
    required this.headerBackground,
    required this.headerBorder,
    required this.headerIconBackground,
    required this.headerIconForeground,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.cardBackground,
    required this.cardShadow,
    required this.primaryText,
    required this.secondaryText,
    required this.yearAccent,
    required this.monthAccent,
    required this.chipBackground,
    required this.chipForeground,
    required this.chevron,
    required this.previewPlaceholder,
  });

  final Color panelGradientStart;
  final Color panelGradientEnd;
  final Color headerBackground;
  final Color headerBorder;
  final Color headerIconBackground;
  final Color headerIconForeground;
  final Color headerTitle;
  final Color headerSubtitle;
  final Color cardBackground;
  final Color cardShadow;
  final Color primaryText;
  final Color secondaryText;
  final Color yearAccent;
  final Color monthAccent;
  final Color chipBackground;
  final Color chipForeground;
  final Color chevron;
  final Color previewPlaceholder;

  factory _DateBrowseColorScheme.fromPalette(GridAppearancePalette palette) {
    final bool isDark = palette.brightness == Brightness.dark;
    if (isDark) {
      return const _DateBrowseColorScheme(
        panelGradientStart: Color.fromARGB(255, 20, 25, 35),
        panelGradientEnd: Color.fromARGB(253, 15, 20, 28),
        headerBackground: Color(0xCC1A2230),
        headerBorder: Color(0x4D5C708A),
        headerIconBackground: Color(0xF0263346),
        headerIconForeground: Color(0xFFF3F4F6),
        headerTitle: Color(0xFFF3F4F6),
        headerSubtitle: Color(0xFF9CA3AF),
        cardBackground: Color(0xCC192331),
        cardShadow: Color(0x73000000),
        primaryText: Color(0xFFF3F4F6),
        secondaryText: Color(0xFF9CA3AF),
        yearAccent: Color(0xFF60A5FA),
        monthAccent: Color(0xFF2DD4BF),
        chipBackground: Color(0xF01E293B),
        chipForeground: Color(0xFFF9FAFB),
        chevron: Color(0xFF94A3B8),
        previewPlaceholder: Color(0xFF2A3342),
      );
    }
    return const _DateBrowseColorScheme(
      panelGradientStart: Color(0xFFF9FBFF),
      panelGradientEnd: Color(0xFFF3F6FB),
      headerBackground: Color(0xEBFFFFFF),
      headerBorder: Color(0x1F111827),
      headerIconBackground: Color(0xF01F2937),
      headerIconForeground: Color(0xFFFFFFFF),
      headerTitle: Color(0xFF111827),
      headerSubtitle: Color(0xFF6B7280),
      cardBackground: Color(0xEAFFFFFF),
      cardShadow: Color(0x22111827),
      primaryText: Color(0xFF111827),
      secondaryText: Color(0xFF6B7280),
      yearAccent: Color(0xFF2563EB),
      monthAccent: Color(0xFF0D9488),
      chipBackground: Color(0xF01F2937),
      chipForeground: Color(0xFFFFFFFF),
      chevron: Color(0xFF9CA3AF),
      previewPlaceholder: Color(0xFFE5E7EB),
    );
  }
}

// new
@immutable
class _DateBrowseYearEntry {
  const _DateBrowseYearEntry({
    required this.year,
    required this.firstDataIndex,
    required this.firstMonthListIndex,
    required this.monthCount,
    required this.totalItemCount,
    required this.previewItems,
  });

  final int year;
  final int firstDataIndex;
  final int firstMonthListIndex;
  final int monthCount;
  final int totalItemCount;
  final List<MediaItem> previewItems;
}

@immutable
class _DateBrowseMonthEntry {
  const _DateBrowseMonthEntry({
    required this.year,
    required this.month,
    required this.firstDataIndex,
    required this.totalItemCount,
    required this.previewItems,
  });

  final int year;
  final int month;
  final int firstDataIndex;
  final int totalItemCount;
  final List<MediaItem> previewItems;
}

class _DateBrowseYearBuilder {
  _DateBrowseYearBuilder({required this.year, required this.firstDataIndex});

  final int year;
  final int firstDataIndex;
  int firstMonthListIndex = -1;
  int monthCount = 0;
  int totalItemCount = 0;
  final List<MediaItem> previewItems = <MediaItem>[];
}

class _DateBrowseMonthBuilder {
  _DateBrowseMonthBuilder({
    required this.year,
    required this.month,
    required this.firstDataIndex,
  });

  final int year;
  final int month;
  final int firstDataIndex;
  int totalItemCount = 0;
  final List<MediaItem> previewItems = <MediaItem>[];
}

enum _DateBrowseRowKind { year, month }

class _DateBrowseRowData {
  const _DateBrowseRowData({
    required this.kind,
    required this.key,
    required this.label,
    this.year,
    this.month,
    this.isSelectedYearAnchor = false,
    required this.primaryStat,
    this.secondaryStat,
    required this.previewItems,
    required this.onTap,
  });

  final _DateBrowseRowKind kind;
  final String key;
  final String label;
  final int? year;
  final int? month;
  final bool isSelectedYearAnchor;
  final int primaryStat;
  final int? secondaryStat;
  final List<MediaItem> previewItems;
  final VoidCallback onTap;
}

// #new
