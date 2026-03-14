import 'dart:async';

import 'package:pizcloud_gallery/media/local_media_scanner.dart';
import 'package:pizcloud_gallery/media/media_repository.dart';

/// Runs device media scan and upserts rows into SQLite.
class LocalMediaScanService {
  LocalMediaScanService({
    LocalMediaScanner? scanner,
    MediaRepository? repository,
    this.scanPageSize = 200,
    this.fullRescanInterval = const Duration(hours: 12),
    this.incrementalOverlap = const Duration(minutes: 2),
    this.includeFileSize = false,
    this.checkPermission = true,
  }) : _scanner =
           scanner ??
           LocalMediaScanner(repository: repository ?? MediaRepository());

  final LocalMediaScanner _scanner;
  final int scanPageSize;
  final Duration fullRescanInterval;
  final Duration incrementalOverlap;
  final bool includeFileSize;
  final bool checkPermission;

  final StreamController<LocalScanProgress> _progressController =
      StreamController<LocalScanProgress>.broadcast();
  final StreamController<LocalScanResult> _resultController =
      StreamController<LocalScanResult>.broadcast();
  bool _disposed = false;
  bool _running = false;
  int _scanToken = 0;

  Stream<LocalScanProgress> get progressStream => _progressController.stream;
  Stream<LocalScanResult> get resultStream => _resultController.stream;
  bool get isRunning => _running;

  Future<LocalScanResult?> startScan({
    bool forceFullScan = false,
    bool includeHiddenAssets = false,
  }) async {
    if (_disposed || _running) {
      return null;
    }
    _running = true;
    final int token = ++_scanToken;
    try {
      final LocalScanResult result = await _scanner.scanAndUpsert(
        pageSize: scanPageSize,
        includeFileSize: includeFileSize,
        checkPermission: checkPermission,
        forceFullScan: forceFullScan,
        fullRescanInterval: fullRescanInterval,
        incrementalOverlap: incrementalOverlap,
        includeHiddenAssets: includeHiddenAssets,
        onProgress: (progress) async {
          if (_disposed ||
              token != _scanToken ||
              _progressController.isClosed) {
            return;
          }
          _progressController.add(progress);
        },
      );
      if (_disposed || token != _scanToken) {
        return null;
      }
      if (!_resultController.isClosed) {
        _resultController.add(result);
      }
      return result;
    } catch (error, stackTrace) {
      if (!_disposed && !_progressController.isClosed) {
        _progressController.addError(error, stackTrace);
      }
      rethrow;
    } finally {
      if (token == _scanToken) {
        _running = false;
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _scanToken += 1;
    if (!_progressController.isClosed) {
      await _progressController.close();
    }
    if (!_resultController.isClosed) {
      await _resultController.close();
    }
  }
}
