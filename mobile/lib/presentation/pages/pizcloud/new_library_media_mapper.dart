import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:openapi/api.dart' as api;
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

String? buildNewLibraryMediaItemId(BaseAsset asset) {
  if (!asset.isImage && !asset.isVideo) {
    return null;
  }

  final localId = asset.localId;
  if (localId != null && localId.isNotEmpty) {
    return _stableLocalId(asset);
  }

  final remoteId = asset.remoteId;
  if (remoteId == null || remoteId.isEmpty) {
    return null;
  }

  return 'remote_$remoteId';
}

MediaItem? mapTimelineAssetToMediaItem(BaseAsset asset) {
  final mediaItemId = buildNewLibraryMediaItemId(asset);
  if (mediaItemId == null) {
    return null;
  }

  final mediaType = asset.isVideo ? MediaType.video : MediaType.photo;
  final durationSeconds = asset.durationInSeconds;
  final duration = durationSeconds != null && durationSeconds > 0 ? Duration(seconds: durationSeconds) : null;

  final localId = asset.localId;
  if (localId != null && localId.isNotEmpty) {
    final remoteAsset = asset is RemoteAsset ? asset : null;
    final originalUrl = LocalDeviceMediaUri.buildOriginalUri(localId);
    final thumb100 = LocalDeviceMediaUri.buildThumbUri(assetId: localId, edge: 100);
    final thumb300 = LocalDeviceMediaUri.buildThumbUri(assetId: localId, edge: 300);
    final thumb600 = LocalDeviceMediaUri.buildThumbUri(assetId: localId, edge: 600);

    return MediaItem(
      id: mediaItemId,
      type: mediaType,
      sourceType: MediaSourceType.local,
      originalUrl: originalUrl,
      previewUrl: thumb600,
      width: _positiveOrNull(asset.width),
      height: _positiveOrNull(asset.height),
      thumbnails: MediaThumbnails(size100: thumb100, size300: thumb300, size600: thumb600),
      localPath: null,
      duration: duration,
      createdAt: asset.createdAt,
      createdLocalAt: remoteAsset?.localDateTime ?? asset.createdAt,
      addedAt: remoteAsset?.uploadedAt,
    );
  }

  final remoteId = asset.remoteId;
  if (remoteId == null || remoteId.isEmpty) {
    return null;
  }
  final captureAt = asset.createdAt;
  final captureLocalAt = asset is RemoteAsset ? (asset.localDateTime ?? asset.createdAt) : asset.createdAt;
  // final addedAt = asset is RemoteAsset ? (asset.uploadedAt ?? asset.createdAt) : asset.createdAt;
  final DateTime? addedAt = asset is RemoteAsset ? asset.uploadedAt : null; // pizcloud

  final thumb100 = getThumbnailUrlForRemoteId(remoteId, type: api.AssetMediaSize.thumbnail);
  final thumb300 = getThumbnailUrlForRemoteId(remoteId, type: api.AssetMediaSize.preview);
  final thumb600 = getPreviewUrlForRemoteId(remoteId);
  final originalUrl = mediaType == MediaType.video
      ? getPlaybackUrlForRemoteId(remoteId)
      : getOriginalUrlForRemoteId(remoteId);

  return MediaItem(
    id: mediaItemId,
    type: mediaType,
    sourceType: MediaSourceType.remote,
    originalUrl: originalUrl,
    previewUrl: thumb600,
    width: _positiveOrNull(asset.width),
    height: _positiveOrNull(asset.height),
    thumbnails: MediaThumbnails(size100: thumb100, size300: thumb300, size600: thumb600),
    localPath: null,
    duration: duration,
    createdAt: captureAt,
    createdLocalAt: captureLocalAt,
    addedAt: addedAt, // pizcloud
  );
}

String _stableLocalId(BaseAsset asset) {
  final remoteId = asset.remoteId;
  if (remoteId != null && remoteId.isNotEmpty) {
    return 'asset_$remoteId';
  }

  return 'local_${asset.localId}';
}

int? _positiveOrNull(int? value) {
  if (value == null || value <= 0) {
    return null;
  }
  return value;
}
