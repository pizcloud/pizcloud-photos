import 'dart:math' as math;

import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/duplicates_api.repository.dart';
import 'package:openapi/api.dart' hide AssetVisibility;
import 'package:openapi/api.dart' as api show AssetVisibility;

class DuplicateAssetItem {
  final RemoteAsset asset;
  final int? fileSizeInBytes;
  final int exifScore;

  const DuplicateAssetItem({required this.asset, required this.fileSizeInBytes, required this.exifScore});
}

class DuplicateGroup {
  final String duplicateId;
  final List<DuplicateAssetItem> assets;

  const DuplicateGroup({required this.duplicateId, required this.assets});
}

class DuplicatesService {
  final DuplicatesApiRepository _repository;

  const DuplicatesService(this._repository);

  Future<List<DuplicateGroup>> getDuplicateGroups() async {
    final groups = await _repository.getDuplicateGroups();

    return groups
        .map((group) {
          final assets = group.assets
              .map(
                (asset) => DuplicateAssetItem(
                  asset: asset.toRemoteAsset(),
                  fileSizeInBytes: asset.exifInfo?.fileSizeInByte,
                  exifScore: _getExifScore(asset.exifInfo),
                ),
              )
              .toList(growable: false);

          return DuplicateGroup(duplicateId: group.duplicateId, assets: assets);
        })
        .where((group) => group.assets.length > 1)
        .toList(growable: false);
  }

  String suggestKeepAssetId(DuplicateGroup group) {
    if (group.assets.isEmpty) {
      throw StateError('Duplicate group must contain at least one asset');
    }

    return _suggestKeepAssetIdFromItems(group.assets);
  }

  Future<void> resolveGroup({
    required DuplicateGroup group,
    required Set<String> keepAssetIds,
    required bool useTrash,
  }) async {
    final deleteIds = group.assets
        .map((item) => item.asset.id)
        .where((assetId) => !keepAssetIds.contains(assetId))
        .toList(growable: false);

    if (deleteIds.isNotEmpty) {
      await _repository.deleteAssets(deleteIds, force: !useTrash);
    }

    // If every asset in the group was trashed/deleted, there is nothing left to mark as resolved.
    if (keepAssetIds.isEmpty) {
      return;
    }

    await _repository.resolveDuplicateGroup(group.duplicateId);
  }

  Future<void> stackGroup(DuplicateGroup group) async {
    final assetIds = group.assets.map((item) => item.asset.id).toList(growable: false);
    await _repository.stackAssets(assetIds);
    await _repository.resolveDuplicateGroup(group.duplicateId);
  }

  Future<void> deduplicateAll({
    required List<DuplicateGroup> groups,
    required Map<String, Set<String>> keepSelectionByGroupId,
    required bool useTrash,
  }) async {
    if (groups.isEmpty) {
      return;
    }

    final duplicateIds = <String>[];
    final deleteIds = <String>[];

    for (final group in groups) {
      if (group.assets.length < 2) {
        continue;
      }

      final selectedKeepAssetIds = keepSelectionByGroupId[group.duplicateId] ?? const <String>{};
      final selectedItems = group.assets
          .where((item) => selectedKeepAssetIds.contains(item.asset.id))
          .toList(growable: false);

      final keepAssetId = switch (selectedItems.length) {
        1 => selectedItems.first.asset.id,
        > 1 => _suggestKeepAssetIdFromItems(selectedItems),
        _ => suggestKeepAssetId(group),
      };
      duplicateIds.add(group.duplicateId);
      deleteIds.addAll(group.assets.map((item) => item.asset.id).where((assetId) => assetId != keepAssetId));
    }

    if (deleteIds.isNotEmpty) {
      await _repository.deleteAssets(deleteIds, force: !useTrash);
    }

    if (duplicateIds.isNotEmpty) {
      await _repository.resolveDuplicateGroups(duplicateIds);
    }
  }

  Future<void> keepAll(List<String> duplicateIds) {
    return _repository.resolveDuplicateGroups(duplicateIds);
  }

  String _suggestKeepAssetIdFromItems(List<DuplicateAssetItem> items) {
    final maxFileSize = items.fold<int>(0, (current, item) => math.max(current, item.fileSizeInBytes ?? 0));
    final largestAssets = items.where((item) => (item.fileSizeInBytes ?? 0) == maxFileSize).toList();
    largestAssets.sort((a, b) => b.exifScore.compareTo(a.exifScore));
    return largestAssets.first.asset.id;
  }
}

int _getExifScore(ExifResponseDto? exif) {
  if (exif == null) {
    return 0;
  }

  return exif.toJson().values.where(_isTruthy).length;
}

bool _isTruthy(Object? value) {
  if (value == null) {
    return false;
  }

  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0 && !value.isNaN;
  }

  if (value is String) {
    return value.isNotEmpty;
  }

  return true;
}

extension on AssetResponseDto {
  RemoteAsset toRemoteAsset() {
    return RemoteAsset(
      id: id,
      name: originalFileName,
      checksum: checksum,
      createdAt: fileCreatedAt,
      uploadedAt: createdAt,
      localDateTime: localDateTime,
      updatedAt: fileModifiedAt,
      ownerId: ownerId,
      visibility: switch (visibility) {
        api.AssetVisibility.timeline => AssetVisibility.timeline,
        api.AssetVisibility.hidden => AssetVisibility.hidden,
        api.AssetVisibility.archive => AssetVisibility.archive,
        api.AssetVisibility.locked => AssetVisibility.locked,
        _ => AssetVisibility.timeline,
      },
      durationInSeconds: duration.toDuration()?.inSeconds ?? 0,
      height: exifInfo?.exifImageHeight?.toInt(),
      width: exifInfo?.exifImageWidth?.toInt(),
      isFavorite: isFavorite,
      livePhotoVideoId: livePhotoVideoId,
      thumbHash: thumbhash,
      localId: null,
      type: type.toAssetType(),
      stackId: stack?.id,
    );
  }
}

extension on AssetTypeEnum {
  AssetType toAssetType() => switch (this) {
    AssetTypeEnum.IMAGE => AssetType.image,
    AssetTypeEnum.VIDEO => AssetType.video,
    AssetTypeEnum.AUDIO => AssetType.audio,
    AssetTypeEnum.OTHER => AssetType.other,
    _ => throw Exception('Unknown AssetType value: $this'),
  };
}
