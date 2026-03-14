import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pizcloud_gallery/media/local_media_scanner.dart';

import 'local_media_scan_service.dart';
import 'local_database_gallery_source.dart';

/// Runs scan separately from grid source and pushes refresh events to DB source.
class LocalGalleryScanProcess {
  static const bool _debugLogs = false;

  LocalGalleryScanProcess({
    required LocalDatabaseGallerySource source,
    LocalMediaScanService? scanService,
    this.periodicInterval = const Duration(minutes: 15),
    this.startImmediately = true,
  }) : _source = source,
       _scanService = scanService ?? LocalMediaScanService();

  final LocalDatabaseGallerySource _source;
  final LocalMediaScanService _scanService;
  final Duration periodicInterval;
  final bool startImmediately;

  StreamSubscription<LocalScanProgress>? _progressSubscription;
  StreamSubscription<LocalScanResult>? _resultSubscription;
  Timer? _periodicTimer;
  bool _disposed = false;
  bool _started = false;

  Future<void> start() async {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    _log(
      '[local_scan] process started (interval: $periodicInterval, startImmediately: $startImmediately)',
    );
    _progressSubscription = _scanService.progressStream.listen((
      LocalScanProgress progress,
    ) {
      if (progress.scanned == progress.total || progress.scanned % 200 == 0) {
        _log(
          '[local_scan] progress scanned=${progress.scanned}/${progress.total}, upserted=${progress.upserted}',
        );
      }
      _source.scheduleRefresh(scannedCount: progress.scanned);
    }, onError: _source.emitError);
    _resultSubscription = _scanService.resultStream.listen((result) {
      unawaited(_handleScanResult(result));
    }, onError: _source.emitError);
    if (periodicInterval > Duration.zero) {
      _periodicTimer = Timer.periodic(periodicInterval, (_) {
        unawaited(triggerScan());
      });
    }
    if (startImmediately) {
      await triggerScan();
    }
  }

  Future<void> triggerScan({bool forceFullScan = false}) async {
    if (_disposed) {
      return;
    }
    try {
      _log('[local_scan] trigger scan (forceFullScan: $forceFullScan)');
      await _scanService.startScan(forceFullScan: forceFullScan);
    } catch (error, stackTrace) {
      _log('[local_scan] scan failed: $error');
      _source.emitError(error, stackTrace);
    }
  }

  Future<void> _handleScanResult(LocalScanResult result) async {
    try {
      // First apply the immediate scan delta.
      await _source.refresh(scannedCount: result.scanned);
      final int indexedCount = await _source.countIndexedItemsInDb();
      // Incremental scans can be tiny (e.g. scanned=1) while DB already has
      // thousands of indexed rows. Promote the source limit to DB count so
      // grid is not capped by the current scan size.
      if (indexedCount > result.scanned) {
        await _source.refresh(scannedCount: indexedCount);
      }
      _log(
        'scan finished: scanned=${result.scanned}, upserted=${result.upserted}, '
        'indexed_db=$indexedCount, full_scan=${result.fullScan}, '
        'permission=${result.permissionGranted}',
      );
      if (result.permissionGranted && indexedCount < result.scanned) {
        _log(
          'possible gap detected: indexed_db($indexedCount) < scanned(${result.scanned})',
        );
      }
    } catch (error, stackTrace) {
      _source.emitError(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    await _progressSubscription?.cancel();
    await _resultSubscription?.cancel();
    await _scanService.dispose();
  }

  void _log(String message) {
    if (!kDebugMode || !_debugLogs) {
      return;
    }
    debugPrint(message);
  }
}
