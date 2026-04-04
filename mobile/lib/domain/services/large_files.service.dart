import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/remote_asset.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/search_api.repository.dart';
import 'package:openapi/api.dart' hide AssetVisibility;
import 'package:openapi/api.dart' as api show AssetVisibility;

class LargeFileAssetItem {
  final RemoteAsset asset;
  final int fileSizeInBytes;

  const LargeFileAssetItem({required this.asset, required this.fileSizeInBytes});
}

class LargeFilesService {
  final SearchApiRepository _repository;
  final RemoteAssetRepository _remoteAssetRepository;

  const LargeFilesService(this._repository, this._remoteAssetRepository);

  Future<List<LargeFileAssetItem>> getLargeFileAssets({int minFileSize = 0}) async {
    final assets = await _repository.searchLargeAssets(minFileSize: minFileSize);
    final localIdsByRemoteId = await _remoteAssetRepository.getLocalIdsByRemoteIds(assets.map((asset) => asset.id));

    final items = assets
        .map(
          (asset) => LargeFileAssetItem(
            // Old behavior:
            // asset: asset.toRemoteAsset(),
            asset: asset.toRemoteAsset(localId: localIdsByRemoteId[asset.id]),
            fileSizeInBytes: asset.exifInfo?.fileSizeInByte ?? 0,
          ),
        )
        .where((item) => item.fileSizeInBytes > minFileSize)
        .toList(growable: false);

    items.sort((a, b) => b.fileSizeInBytes.compareTo(a.fileSizeInBytes));
    return items;
  }
}

extension on AssetResponseDto {
  RemoteAsset toRemoteAsset({String? localId}) {
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
      // localId: null,
      localId: localId,
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
