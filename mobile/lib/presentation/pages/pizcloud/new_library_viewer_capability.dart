import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';

class NewLibraryViewerCapability {
  const NewLibraryViewerCapability({
    required this.isReadonlyMode,
    required this.isOwner,
    required this.hasRemote,
    required this.hasLocal,
    required this.isFavorite,
    required this.isArchived,
    required this.isLocked,
  });

  final bool isReadonlyMode;
  final bool isOwner;
  final bool hasRemote;
  final bool hasLocal;
  final bool isFavorite;
  final bool isArchived;
  final bool isLocked;

  bool get canShare => true;
  bool get canShareLink => !isReadonlyMode && hasRemote;
  bool get canDownload => !isReadonlyMode && hasRemote && !hasLocal;
  bool get canUpload => !isReadonlyMode && hasLocal && !hasRemote;
  bool get canFavorite => !isReadonlyMode && hasRemote && isOwner && !isFavorite;
  bool get canUnfavorite => !isReadonlyMode && hasRemote && isOwner && isFavorite;
  bool get canArchive => !isReadonlyMode && hasRemote && isOwner && !isArchived;
  bool get canUnarchive => !isReadonlyMode && hasRemote && isOwner && isArchived;
  bool get canMoveToLockFolder => !isReadonlyMode && hasRemote && isOwner && !isLocked;
  bool get canRemoveFromLockFolder => !isReadonlyMode && hasRemote && isOwner && isLocked;
  bool get canDeleteRemoteAndLocal => !isReadonlyMode && hasRemote && isOwner;
  bool get canDeleteLocal => !isReadonlyMode && hasLocal;
  bool get canAddToAlbum => !isReadonlyMode && hasRemote;
  bool get canViewInTimeline => hasRemote && isOwner;

  factory NewLibraryViewerCapability.fromAsset({
    required BaseAsset asset,
    required bool isReadonlyMode,
    required String? currentUserId,
  }) {
    final RemoteAsset? remoteAsset = asset is RemoteAsset ? asset : null;
    final bool isOwner = remoteAsset != null && remoteAsset.ownerId == currentUserId;
    final AssetVisibility visibility = remoteAsset?.visibility ?? AssetVisibility.timeline;

    return NewLibraryViewerCapability(
      isReadonlyMode: isReadonlyMode,
      isOwner: isOwner,
      hasRemote: asset.hasRemote,
      hasLocal: asset.hasLocal,
      isFavorite: asset.isFavorite,
      isArchived: visibility == AssetVisibility.archive,
      isLocked: visibility == AssetVisibility.locked,
    );
  }
}
