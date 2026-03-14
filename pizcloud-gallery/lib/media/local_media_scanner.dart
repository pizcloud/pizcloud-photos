import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import 'media_models.dart';
import 'media_repository.dart';

typedef LocalScanProgressCallback =
    Future<void> Function(LocalScanProgress progress);

class LocalMediaScanner {
  LocalMediaScanner({required MediaRepository repository})
    : _repository = repository;

  static const String _metaKeyLastFullScanMs = 'local_scan_last_full_ms';
  static const String _metaKeyMaxModifiedMs = 'local_scan_max_modified_ms';
  final MediaRepository _repository;

  Future<LocalScanResult> scanAndUpsert({
    int pageSize = 200,
    bool includeFileSize = false,
    bool checkPermission = true,
    bool forceFullScan = false,
    Duration fullRescanInterval = const Duration(hours: 12),
    Duration incrementalOverlap = const Duration(minutes: 2),
    bool includeHiddenAssets = false,
    LocalScanProgressCallback? onProgress,
  }) async {
    if (checkPermission) {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        return LocalScanResult(
          scanned: 0,
          upserted: 0,
          permissionGranted: false,
          fullScan: false,
          reconciled: 0,
        );
      }
    }

    final DateTime scanStartedAt = DateTime.now();
    final bool shouldRunFullScan =
        forceFullScan ||
        await _shouldRunFullScan(
          now: scanStartedAt,
          fullRescanInterval: fullRescanInterval,
        );
    final DateTime? incrementalSince = shouldRunFullScan
        ? null
        : await _resolveIncrementalSince(overlap: incrementalOverlap);
    final FilterOptionGroup filterOption = _buildFilterOption(
      fullScan: shouldRunFullScan,
      incrementalSince: incrementalSince,
      includeHiddenAssets: includeHiddenAssets,
    );
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: filterOption,
    );

    final AssetPathEntity? path = paths.isEmpty ? null : paths.first;
    final int total = path == null ? 0 : await path.assetCountAsync;
    int page = 0;
    int scanned = 0;
    int upserted = 0;
    DateTime? latestModifiedSeen;

    while (path != null && scanned < total) {
      final assets = await path.getAssetListPaged(page: page, size: pageSize);
      if (assets.isEmpty) {
        break;
      }

      final items = <MediaItem>[];
      for (final asset in assets) {
        if (asset.type == AssetType.other) {
          continue;
        }
        final type = asset.type == AssetType.video
            ? MediaType.video
            : MediaType.photo;
        final DateTime modifiedAt = _effectiveModifiedAt(asset);
        if (latestModifiedSeen == null ||
            modifiedAt.isAfter(latestModifiedSeen)) {
          latestModifiedSeen = modifiedAt;
        }
        int? durationMs;
        if (type == MediaType.video) {
          durationMs = (asset.duration * 1000).round();
        }

        int? sizeBytes;
        String? fileName;
        if (includeFileSize) {
          final file = await asset.originFile;
          if (file != null) {
            sizeBytes = await file.length();
            fileName = p.basename(file.path);
          }
        }

        items.add(
          MediaItem(
            localId: asset.id,
            type: type,
            fileName: fileName,
            width: asset.width,
            height: asset.height,
            durationMs: durationMs,
            sizeBytes: sizeBytes,
            createdAt: asset.createDateTime,
            modifiedAt: asset.modifiedDateTime,
            syncState: SyncState.localOnly,
            updatedAt: scanStartedAt,
          ),
        );
      }

      if (items.isNotEmpty) {
        upserted += await _repository.upsertLocalItems(
          items,
          updatedAt: scanStartedAt,
        );
      }

      scanned += assets.length;
      if (onProgress != null) {
        await onProgress(
          LocalScanProgress(
            scanned: scanned,
            upserted: upserted,
            total: total,
            fullScan: shouldRunFullScan,
            incrementalSince: incrementalSince,
          ),
        );
      }
      page += 1;
    }

    int reconciled = 0;
    if (shouldRunFullScan) {
      reconciled = await _repository.reconcileMissingLocalItems(
        scanMarker: scanStartedAt,
      );
      await _repository.setMetaInt(
        _metaKeyLastFullScanMs,
        scanStartedAt.millisecondsSinceEpoch,
      );
    }
    if (latestModifiedSeen != null) {
      await _repository.setMetaInt(
        _metaKeyMaxModifiedMs,
        latestModifiedSeen.millisecondsSinceEpoch,
      );
    } else if (shouldRunFullScan) {
      await _repository.setMetaInt(_metaKeyMaxModifiedMs, 0);
    }

    return LocalScanResult(
      scanned: scanned,
      upserted: upserted,
      permissionGranted: true,
      fullScan: shouldRunFullScan,
      reconciled: reconciled,
      incrementalSince: incrementalSince,
    );
  }

  Future<bool> _shouldRunFullScan({
    required DateTime now,
    required Duration fullRescanInterval,
  }) async {
    if (fullRescanInterval <= Duration.zero) {
      return true;
    }
    final int? lastFullScanMs = await _repository.getMetaInt(
      _metaKeyLastFullScanMs,
    );
    if (lastFullScanMs == null || lastFullScanMs <= 0) {
      return true;
    }
    final DateTime lastFullScan = DateTime.fromMillisecondsSinceEpoch(
      lastFullScanMs,
    );
    return now.difference(lastFullScan) >= fullRescanInterval;
  }

  Future<DateTime?> _resolveIncrementalSince({
    required Duration overlap,
  }) async {
    final int? maxModifiedMs = await _repository.getMetaInt(
      _metaKeyMaxModifiedMs,
    );
    DateTime? base;
    if (maxModifiedMs != null && maxModifiedMs > 0) {
      base = DateTime.fromMillisecondsSinceEpoch(maxModifiedMs);
    } else {
      base = await _repository.latestLocalModifiedAt();
    }
    if (base == null) {
      return null;
    }
    final DateTime overlapped = base.subtract(overlap);
    final DateTime zero = DateTime.fromMillisecondsSinceEpoch(0);
    return overlapped.isBefore(zero) ? zero : overlapped;
  }

  FilterOptionGroup _buildFilterOption({
    required bool fullScan,
    required DateTime? incrementalSince,
    required bool includeHiddenAssets,
  }) {
    final FilterOptionGroup group = FilterOptionGroup(
      containsPathModified: true,
      includeHiddenAssets: includeHiddenAssets,
      orders: const <OrderOption>[
        OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );
    if (!fullScan && incrementalSince != null) {
      group.updateTimeCond = DateTimeCond(
        min: incrementalSince,
        max: DateTime.now(),
      );
    }
    return group;
  }

  DateTime _effectiveModifiedAt(AssetEntity asset) {
    final DateTime modified = asset.modifiedDateTime;
    final DateTime created = asset.createDateTime;
    return modified.isAfter(created) ? modified : created;
  }
}

class LocalScanResult {
  const LocalScanResult({
    required this.scanned,
    required this.upserted,
    required this.permissionGranted,
    this.fullScan = false,
    this.reconciled = 0,
    this.incrementalSince,
  });

  final int scanned;
  final int upserted;
  final bool permissionGranted;
  final bool fullScan;
  final int reconciled;
  final DateTime? incrementalSince;
}

class LocalScanProgress {
  const LocalScanProgress({
    required this.scanned,
    required this.upserted,
    required this.total,
    this.fullScan = false,
    this.incrementalSince,
  });

  final int scanned;
  final int upserted;
  final int total;
  final bool fullScan;
  final DateTime? incrementalSince;
}
