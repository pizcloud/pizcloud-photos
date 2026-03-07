import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/album/album_selector.widget.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/base_bottom_sheet.widget.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/current_asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/platform_sheet.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

import 'new_library_asset_resolver.dart';
import 'new_library_timeline_gallery_source.dart';
import 'new_library_viewer_capability.dart';

class NewLibraryViewerActionRunner {
  const NewLibraryViewerActionRunner({required WidgetRef ref, required TimelineGallerySource source})
    : _ref = ref,
      _source = source;

  final WidgetRef _ref;
  final TimelineGallerySource _source;

  NewLibraryViewerCapability capabilityForItemSync(MediaItem item) {
    final bool isReadonlyMode = _ref.read(readonlyModeProvider);
    final String? currentUserId = _ref.read(currentUserProvider)?.id;
    final BaseAsset? cached = _ref.read(newLibraryAssetResolverProvider).resolveCached(item, source: _source);
    if (cached != null) {
      return NewLibraryViewerCapability.fromAsset(
        asset: cached,
        isReadonlyMode: isReadonlyMode,
        currentUserId: currentUserId,
      );
    }

    // Fallback capability when cache has not loaded this item yet.
    return NewLibraryViewerCapability(
      isReadonlyMode: isReadonlyMode,
      isOwner: false,
      hasRemote: item.sourceType == MediaSourceType.remote,
      hasLocal: item.sourceType == MediaSourceType.local,
      isFavorite: false,
      isArchived: false,
      isLocked: false,
    );
  }

  bool canDeleteItemSync(MediaItem item) {
    return capabilityForItemSync(item).canDeleteRemoteAndLocal;
  }

  Future<void> onShareRequested(MediaItem item, BuildContext context) async {
    final _ResolvedAsset resolved = await _resolveOrThrow(
      item,
      context: context,
      guard: (capability) => capability.canShare,
      guardMessage: 'Share is not available for this item.',
    );

    final ActionResult result = await _runWithCurrentAsset(
      resolved.asset,
      () => _ref.read(actionProvider.notifier).shareAssets(ActionSource.viewer, context),
    );

    if (!result.success) {
      throw StateError(result.error ?? 'Share failed');
    }
  }

  Future<void> onDeleteRequested(MediaItem item, BuildContext context) async {
    final _ResolvedAsset resolved = await _resolveOrThrow(
      item,
      context: context,
      guard: (capability) => capability.canDeleteRemoteAndLocal,
      guardMessage: 'Delete is not available for this item.',
    );

    final ActionResult result = await _runWithCurrentAsset(
      resolved.asset,
      () => _ref.read(actionProvider.notifier).trashRemoteAndDeleteLocal(ActionSource.viewer),
    );

    if (!result.success) {
      throw StateError(result.error ?? 'Delete failed');
    }
  }

  Future<void> favorite(MediaItem item, BuildContext context) async {
    await _runAction(
      item,
      context: context,
      guard: (capability) => capability.canFavorite,
      guardMessage: 'Favorite is not available for this item.',
      action: () => _ref.read(actionProvider.notifier).favorite(ActionSource.viewer),
    );
  }

  Future<void> unfavorite(MediaItem item, BuildContext context) async {
    await _runAction(
      item,
      context: context,
      guard: (capability) => capability.canUnfavorite,
      guardMessage: 'Unfavorite is not available for this item.',
      action: () => _ref.read(actionProvider.notifier).unFavorite(ActionSource.viewer),
    );
  }

  Future<void> archive(MediaItem item, BuildContext context) async {
    await _runAction(
      item,
      context: context,
      guard: (capability) => capability.canArchive,
      guardMessage: 'Archive is not available for this item.',
      action: () => _ref.read(actionProvider.notifier).archive(ActionSource.viewer),
      successMessage: 'Moved to archive',
    );
  }

  Future<void> unarchive(MediaItem item, BuildContext context) async {
    await _runAction(
      item,
      context: context,
      guard: (capability) => capability.canUnarchive,
      guardMessage: 'Unarchive is not available for this item.',
      action: () => _ref.read(actionProvider.notifier).unArchive(ActionSource.viewer),
      successMessage: 'Removed from archive',
    );
  }

  Future<void> moveToLockFolder(MediaItem item, BuildContext context) async {
    await _runAction(
      item,
      context: context,
      guard: (capability) => capability.canMoveToLockFolder,
      guardMessage: 'Move to locked folder is not available for this item.',
      action: () => _ref.read(actionProvider.notifier).moveToLockFolder(ActionSource.viewer),
      successMessage: 'Moved to locked folder',
    );
  }

  Future<void> removeFromLockFolder(MediaItem item, BuildContext context) async {
    await _runAction(
      item,
      context: context,
      guard: (capability) => capability.canRemoveFromLockFolder,
      guardMessage: 'Remove from locked folder is not available for this item.',
      action: () => _ref.read(actionProvider.notifier).removeFromLockFolder(ActionSource.viewer),
      successMessage: 'Removed from locked folder',
    );
  }

  Future<void> download(MediaItem item, BuildContext context) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: (capability) => capability.canDownload,
      guardMessage: 'Download is only available for remote-only items.',
    );
    if (resolved == null) {
      return;
    }

    final ActionResult result = await _runWithCurrentAsset(
      resolved.asset,
      () => _ref.read(actionProvider.notifier).downloadAll(ActionSource.viewer),
    );

    if (!result.success) {
      _showError(context, result.error ?? 'Download failed');
      return;
    }

    // Keep behavior aligned with existing DownloadActionButton.
    Future<void>.delayed(const Duration(seconds: 1), () async {
      final backgroundManager = _ref.read(backgroundSyncProvider);
      await backgroundManager.syncLocal();
      await backgroundManager.hashAssets();
    });
    _showSuccess(context, 'Download started');
  }

  Future<void> upload(MediaItem item, BuildContext context) async {
    await _runAction(
      item,
      context: context,
      guard: (capability) => capability.canUpload,
      guardMessage: 'Upload is only available for local-only items.',
      action: () => _ref.read(actionProvider.notifier).upload(ActionSource.viewer),
      successMessage: 'Upload started',
    );
  }

  Future<void> deleteLocal(MediaItem item, BuildContext context) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: (capability) => capability.canDeleteLocal,
      guardMessage: 'Delete local is not available for this item.',
    );
    if (resolved == null) {
      return;
    }

    final ActionResult? result = await _runWithCurrentAsset(
      resolved.asset,
      () => _ref.read(actionProvider.notifier).deleteLocal(ActionSource.viewer, context),
    );
    if (result == null) {
      return;
    }
    if (!result.success) {
      _showError(context, result.error ?? 'Delete local failed');
      return;
    }
    if (result.count > 0) {
      _showSuccess(context, 'Deleted local copy');
    }
  }

  Future<void> shareLink(MediaItem item, BuildContext context) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: (capability) => capability.canShareLink,
      guardMessage: 'Share link is not available for this item.',
    );
    if (resolved == null) {
      return;
    }

    await _runWithCurrentAsset(
      resolved.asset,
      () => _ref.read(actionProvider.notifier).shareLink(ActionSource.viewer, context),
    );
  }

  Future<void> addToAlbum(MediaItem item, BuildContext context) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: (capability) => capability.canAddToAlbum,
      guardMessage: 'Add to album is not available for this item.',
    );
    if (resolved == null) {
      return;
    }

    final String? remoteId = resolved.asset.remoteId;
    if (remoteId == null || remoteId.isEmpty) {
      _showError(context, 'Unable to resolve remote id for this item.');
      return;
    }

    await showPlatformModalSheet(
      context: context,
      material: MaterialModalSheetData(isScrollControlled: true, backgroundColor: Colors.transparent),
      builder: (_) {
        return platformSheetWrapper(
          context,
          BaseBottomSheet(
            actions: const <Widget>[],
            slivers: <Widget>[
              AlbumSelector(
                onAlbumSelected: (RemoteAlbum album) async {
                  final int addedCount = await _ref.read(remoteAlbumProvider.notifier).addAssets(album.id, <String>[
                    remoteId,
                  ]);
                  if (!context.mounted) {
                    return;
                  }
                  if (addedCount == 0) {
                    _showInfo(context, 'Item already exists in this album.');
                  } else {
                    _showSuccess(context, 'Added to album');
                  }
                  await Navigator.of(context).maybePop();
                },
              ),
            ],
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.95,
            expand: false,
            backgroundColor: context.isDarkTheme ? Colors.black : Colors.white,
          ),
        );
      },
    );
  }

  Future<void> viewInTimeline(MediaItem item, BuildContext context) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: (capability) => capability.canViewInTimeline,
      guardMessage: 'View in timeline is not available for this item.',
    );
    if (resolved == null) {
      return;
    }

    await context.maybePop();
    await context.navigateTo(const TabShellRoute(children: <PageRouteInfo>[MainTimelineRoute()]));
    EventStream.shared.emit(ScrollToDateEvent(resolved.asset.createdAt));
  }

  Future<_ResolvedAsset> _resolveOrThrow(
    MediaItem item, {
    required BuildContext context,
    required bool Function(NewLibraryViewerCapability capability) guard,
    required String guardMessage,
  }) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: guard,
      guardMessage: guardMessage,
    );
    if (resolved == null) {
      throw StateError(guardMessage);
    }
    return resolved;
  }

  Future<_ResolvedAsset?> _resolveOrNotify(
    MediaItem item, {
    required BuildContext context,
    required bool Function(NewLibraryViewerCapability capability) guard,
    required String guardMessage,
  }) async {
    final BaseAsset? asset = await _ref.read(newLibraryAssetResolverProvider).resolve(item, source: _source);
    if (asset == null) {
      _showError(context, 'Unable to resolve asset for this item.');
      return null;
    }

    final NewLibraryViewerCapability capability = _capabilityFromAsset(asset);
    if (!guard(capability)) {
      _showInfo(context, guardMessage);
      return null;
    }
    return _ResolvedAsset(asset: asset, capability: capability);
  }

  NewLibraryViewerCapability _capabilityFromAsset(BaseAsset asset) {
    return NewLibraryViewerCapability.fromAsset(
      asset: asset,
      isReadonlyMode: _ref.read(readonlyModeProvider),
      currentUserId: _ref.read(currentUserProvider)?.id,
    );
  }

  Future<void> _runAction(
    MediaItem item, {
    required BuildContext context,
    required bool Function(NewLibraryViewerCapability capability) guard,
    required String guardMessage,
    required Future<ActionResult> Function() action,
    String? successMessage,
  }) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: guard,
      guardMessage: guardMessage,
    );
    if (resolved == null) {
      return;
    }

    final ActionResult result = await _runWithCurrentAsset(resolved.asset, action);
    if (!result.success) {
      _showError(context, result.error ?? 'Action failed');
      return;
    }
    if (successMessage != null && successMessage.isNotEmpty) {
      _showSuccess(context, successMessage);
    }
  }

  Future<T> _runWithCurrentAsset<T>(BaseAsset asset, Future<T> Function() action) async {
    final BaseAsset? previousAsset = _ref.read(currentAssetNotifier);
    _ref.read(currentAssetNotifier.notifier).setAsset(asset);
    try {
      return await action();
    } finally {
      // Old behavior had no restore because actions were executed only in AssetViewer flow.
      // Here we restore previous state to avoid leaking viewer state across unrelated pages.
      if (previousAsset != null && previousAsset != asset) {
        _ref.read(currentAssetNotifier.notifier).setAsset(previousAsset);
      } else if (previousAsset == null) {
        _ref.invalidate(currentAssetNotifier);
      }
    }
  }

  void _showSuccess(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ImmichToast.show(context: context, msg: message, toastType: ToastType.success);
  }

  void _showInfo(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ImmichToast.show(context: context, msg: message, toastType: ToastType.info);
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ImmichToast.show(context: context, msg: message, toastType: ToastType.error);
  }
}

class _ResolvedAsset {
  const _ResolvedAsset({required this.asset, required this.capability});

  final BaseAsset asset;
  final NewLibraryViewerCapability capability;
}
