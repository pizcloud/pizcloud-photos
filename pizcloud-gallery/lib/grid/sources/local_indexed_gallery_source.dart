import 'dart:async';

import 'package:pizcloud_gallery/media/local_media_scanner.dart';
import 'package:pizcloud_gallery/media/media_repository.dart';

import '../media_item.dart';
import '../piz_gallery_source.dart';
import 'local_database_gallery_source.dart';
import 'local_media_scan_service.dart';

/// Composes:
/// - [LocalDatabaseGallerySource] for reading indexed rows from SQLite
/// - [LocalMediaScanService] for scanning + upsert in background
class AutoScanLocalIndexedSource extends PizGallerySource {
  factory AutoScanLocalIndexedSource({
    MediaRepository? repository,
    LocalMediaScanner? scanner,
    int initialLoadCount = 120,
    int? maxItems,
    int scanPageSize = 200,
    bool scanInBackground = true,
    Duration updateDebounce = const Duration(milliseconds: 120),
    Duration fullRescanInterval = const Duration(hours: 12),
    Duration incrementalOverlap = const Duration(minutes: 2),
    bool includeFileSize = false,
    bool checkPermission = true,
  }) {
    final MediaRepository resolvedRepository = repository ?? MediaRepository();
    return AutoScanLocalIndexedSource.compose(
      indexedSource: LocalDatabaseGallerySource(
        repository: resolvedRepository,
        initialLoadCount: initialLoadCount,
        maxItems: maxItems,
        updateDebounce: updateDebounce,
      ),
      scanService: LocalMediaScanService(
        scanner: scanner ?? LocalMediaScanner(repository: resolvedRepository),
        repository: resolvedRepository,
        scanPageSize: scanPageSize,
        fullRescanInterval: fullRescanInterval,
        incrementalOverlap: incrementalOverlap,
        includeFileSize: includeFileSize,
        checkPermission: checkPermission,
      ),
      scanInBackground: scanInBackground,
    );
  }

  AutoScanLocalIndexedSource.compose({
    required LocalDatabaseGallerySource indexedSource,
    required LocalMediaScanService scanService,
    this.scanInBackground = true,
  }) : _indexedSource = indexedSource,
       _scanService = scanService {
    _scanProgressSubscription = _scanService.progressStream.listen((progress) {
      _indexedSource.scheduleRefresh(scannedCount: progress.scanned);
    }, onError: _onScanError);
    _scanResultSubscription = _scanService.resultStream.listen((_) {
      _refreshAfterScan(force: true);
    }, onError: _onScanError);
  }

  final LocalDatabaseGallerySource _indexedSource;
  final LocalMediaScanService _scanService;
  final bool scanInBackground;
  StreamSubscription<dynamic>? _scanProgressSubscription;
  StreamSubscription<dynamic>? _scanResultSubscription;
  bool _disposed = false;

  @override
  Future<List<MediaItem>> loadInitial() async {
    final List<MediaItem> initial = await _indexedSource.loadInitial();
    if (scanInBackground) {
      unawaited(startScan());
    }
    return initial;
  }

  /// Triggers one scan cycle.
  Future<void> startScan({bool forceFullScan = false}) async {
    if (_disposed) {
      return;
    }
    try {
      await _scanService.startScan(forceFullScan: forceFullScan);
    } catch (error, stackTrace) {
      _indexedSource.emitError(error, stackTrace);
    }
  }

  @override
  Stream<List<MediaItem>> watchUpdates() => _indexedSource.watchUpdates();

  @override
  Future<void> removeItem(MediaItem item) {
    return _indexedSource.removeItem(item);
  }

  void _refreshAfterScan({required bool force}) {
    unawaited(_refreshAfterScanSafe(force: force));
  }

  Future<void> _refreshAfterScanSafe({required bool force}) async {
    try {
      await _indexedSource.refresh(force: force);
    } catch (error, stackTrace) {
      _indexedSource.emitError(error, stackTrace);
    }
  }

  void _onScanError(Object error, StackTrace stackTrace) {
    _indexedSource.emitError(error, stackTrace);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _scanProgressSubscription?.cancel();
    await _scanResultSubscription?.cancel();
    await _scanService.dispose();
    await _indexedSource.dispose();
  }
}

/// Default local indexed source with background scan enabled.
class LocalIndexedGallerySource extends PizGallerySource {
  LocalIndexedGallerySource({
    MediaRepository? repository,
    LocalMediaScanner? scanner,
    int initialLoadCount = 120,
    int? maxItems,
    int scanPageSize = 200,
    bool scanInBackground = true,
    Duration updateDebounce = const Duration(milliseconds: 120),
    Duration fullRescanInterval = const Duration(hours: 12),
    Duration incrementalOverlap = const Duration(minutes: 2),
    bool includeFileSize = false,
    bool checkPermission = true,
  }) : _delegate = AutoScanLocalIndexedSource(
         repository: repository,
         scanner: scanner,
         initialLoadCount: initialLoadCount,
         maxItems: maxItems,
         scanPageSize: scanPageSize,
         scanInBackground: scanInBackground,
         updateDebounce: updateDebounce,
         fullRescanInterval: fullRescanInterval,
         incrementalOverlap: incrementalOverlap,
         includeFileSize: includeFileSize,
         checkPermission: checkPermission,
       );

  final AutoScanLocalIndexedSource _delegate;

  Future<void> startScan({bool forceFullScan = false}) {
    return _delegate.startScan(forceFullScan: forceFullScan);
  }

  @override
  Future<List<MediaItem>> loadInitial() => _delegate.loadInitial();

  @override
  Stream<List<MediaItem>> watchUpdates() => _delegate.watchUpdates();

  @override
  Future<void> removeItem(MediaItem item) => _delegate.removeItem(item);

  @override
  Future<void> dispose() => _delegate.dispose();
}
