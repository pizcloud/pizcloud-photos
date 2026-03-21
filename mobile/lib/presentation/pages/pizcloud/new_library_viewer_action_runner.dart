import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/album/album_selector.widget.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/base_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/current_asset.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/upload.service.dart';
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
      isImage: item.type == MediaType.photo,
      isFavorite: false,
      isArchived: false,
      isLocked: false,
    );
  }

  bool canDeleteItemSync(MediaItem item) {
    return capabilityForItemSync(item).canDeleteRemoteAndLocal;
  }

  bool canEditImageSync(MediaItem item) {
    return capabilityForItemSync(item).canEditImage;
  }

  bool canUploadItemSync(MediaItem item) {
    return capabilityForItemSync(item).canUpload;
  }

  bool canAddToAlbumSync(MediaItem item) {
    return capabilityForItemSync(item).canAddToAlbum;
  }

  Future<bool> shareMany(List<MediaItem> items, BuildContext context) async {
    final List<_ResolvedAsset> resolved = await _resolveMany(
      items,
      context: context,
      guard: (capability) => capability.canShare,
    );
    if (resolved.isEmpty) {
      _showInfo(context, 'No selected item can be shared.');
      return false;
    }

    final ActionResult result = await _runWithTimelineSelection(
      resolved.map((entry) => entry.asset),
      () => _ref.read(actionProvider.notifier).shareAssets(ActionSource.timeline, context),
    );
    if (!result.success) {
      _showError(context, result.error ?? 'Share failed');
      return false;
    }
    return true;
  }

  Future<bool> addToAlbumMany(List<MediaItem> items, BuildContext context) async {
    final List<_ResolvedAsset> resolved = await _resolveMany(
      items,
      context: context,
      guard: (capability) => capability.canAddToAlbum,
    );
    if (resolved.isEmpty) {
      _showInfo(context, 'No selected item can be added to album.');
      return false;
    }

    final List<String> remoteIds = resolved
        .map((entry) => entry.asset.remoteId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (remoteIds.isEmpty) {
      _showInfo(context, 'Unable to resolve remote ids for selected items.');
      return false;
    }

    bool completed = false;
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
                  final int addedCount = await _ref.read(remoteAlbumProvider.notifier).addAssets(album.id, remoteIds);
                  if (!context.mounted) {
                    return;
                  }

                  if (addedCount == 0) {
                    _showInfo(context, 'Selected items already exist in this album.');
                  } else if (addedCount < remoteIds.length) {
                    _showInfo(context, 'Added $addedCount/${remoteIds.length} item(s) to album.');
                  } else {
                    _showSuccess(context, 'Added to album');
                  }
                  completed = true;
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

    return completed;
  }

  Future<bool> uploadMany(List<MediaItem> items, BuildContext context) async {
    final List<_ResolvedAsset> resolved = await _resolveMany(
      items,
      context: context,
      guard: (capability) => capability.canUpload,
    );
    if (resolved.isEmpty) {
      _showInfo(context, 'Upload is only available for local-only items.');
      return false;
    }

    final ActionResult result = await _runWithTimelineSelection(
      resolved.map((entry) => entry.asset),
      () => _ref.read(actionProvider.notifier).upload(ActionSource.timeline),
    );
    if (!result.success) {
      _showError(context, _resolveUploadActionErrorMessage(context, result.error));
      return false;
    }

    _showSuccess(context, 'Upload started');

    for (final BaseAsset asset in resolved.map((entry) => entry.asset)) {
      if (asset is LocalAsset) {
        unawaited(_watchManualUploadForbiddenError(context: context, localAssetId: asset.id));
      }
    }

    return true;
  }

  Future<bool> downloadMany(List<MediaItem> items, BuildContext context) async {
    final List<_ResolvedAsset> resolved = await _resolveMany(
      items,
      context: context,
      guard: (capability) => capability.canDownload,
    );
    if (resolved.isEmpty) {
      _showInfo(context, 'Download is only available for remote-only items.');
      return false;
    }

    final ActionResult result = await _runWithTimelineSelection(
      resolved.map((entry) => entry.asset),
      () => _ref.read(actionProvider.notifier).downloadAll(ActionSource.timeline),
    );
    if (!result.success) {
      _showError(context, result.error ?? 'Download failed');
      return false;
    }

    Future<void>.delayed(const Duration(seconds: 1), () async {
      final backgroundManager = _ref.read(backgroundSyncProvider);
      await backgroundManager.syncLocal();
      await backgroundManager.hashAssets();
    });
    _showSuccess(context, 'Download started');
    return true;
  }

  Future<bool> deleteMany(List<MediaItem> items, BuildContext context) async {
    final List<_ResolvedAsset> resolved = await _resolveMany(
      items,
      context: context,
      guard: (capability) => capability.canDeleteRemoteAndLocal,
    );
    if (resolved.isEmpty) {
      _showInfo(context, 'Delete is not available for selected items.');
      return false;
    }

    final bool? confirm = await showPlatformDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('delete'.t(context: dialogContext)),
        content: Text('delete_action_confirmation_message'.t(context: dialogContext)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.t(context: dialogContext)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'confirm'.t(context: dialogContext),
              style: TextStyle(color: dialogContext.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return false;
    }

    final ActionResult result = await _runWithTimelineSelection(
      resolved.map((entry) => entry.asset),
      () => _ref.read(actionProvider.notifier).trashRemoteAndDeleteLocal(ActionSource.timeline),
    );
    if (!result.success) {
      _showError(context, _resolveDeleteErrorMessage(context, result.error));
      return false;
    }

    final String successMessage = 'delete_action_prompt'.t(context: context, args: {'count': result.count.toString()});
    _showSuccess(context, successMessage);
    return true;
  }

  Future<bool> deleteLocalMany(List<MediaItem> items, BuildContext context) async {
    final List<_ResolvedAsset> resolved = await _resolveMany(
      items,
      context: context,
      guard: (capability) => capability.canDeleteLocal,
    );
    if (resolved.isEmpty) {
      _showInfo(context, 'Delete local is not available for selected items.');
      return false;
    }

    final ActionResult? result = await _runWithTimelineSelection(
      resolved.map((entry) => entry.asset),
      () => _ref.read(actionProvider.notifier).deleteLocal(ActionSource.timeline, context),
    );
    if (result == null) {
      return false;
    }
    if (!result.success) {
      _showError(context, result.error ?? 'Delete local failed');
      return false;
    }
    if (result.count <= 0) {
      return false;
    }

    final String successMessage = 'delete_local_action_prompt'.t(
      context: context,
      args: {'count': result.count.toString()},
    );
    _showSuccess(context, successMessage);
    return true;
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
      final errorMessage = _resolveDeleteErrorMessage(context, result.error);
      // throw StateError(result.error ?? 'Delete failed');
      throw _UserVisibleActionError(errorMessage);
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
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: (capability) => capability.canUpload,
      guardMessage: 'Upload is only available for local-only items.',
    );
    if (resolved == null) {
      return;
    }

    final ActionResult result = await _runWithCurrentAsset(
      resolved.asset,
      () => _ref.read(actionProvider.notifier).upload(ActionSource.viewer),
    );
    if (!result.success) {
      _showError(context, _resolveUploadActionErrorMessage(context, result.error));
      return;
    }

    _showSuccess(context, 'Upload started');

    // return;
    final BaseAsset asset = resolved.asset;
    if (asset is LocalAsset) {
      unawaited(_watchManualUploadForbiddenError(context: context, localAssetId: asset.id));
    }
  }

  Future<void> editImage(MediaItem item, BuildContext context) async {
    final _ResolvedAsset? resolved = await _resolveOrNotify(
      item,
      context: context,
      guard: (capability) => capability.canEditImage,
      guardMessage: 'Edit is available for images only.',
    );
    if (resolved == null) {
      return;
    }

    final Image image = Image(image: getFullImageProvider(resolved.asset));
    await context.pushRoute(DriftEditImageRoute(asset: resolved.asset, image: image, isEdited: false));
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

  Future<List<_ResolvedAsset>> _resolveMany(
    List<MediaItem> items, {
    required BuildContext context,
    bool Function(NewLibraryViewerCapability capability)? guard,
  }) async {
    if (items.isEmpty) {
      return const <_ResolvedAsset>[];
    }

    final NewLibraryAssetResolver resolver = _ref.read(newLibraryAssetResolverProvider);
    final List<_ResolvedAsset> output = <_ResolvedAsset>[];
    final Set<String> seenAssetKeys = <String>{};
    int unresolvedCount = 0;

    for (final MediaItem item in items) {
      final BaseAsset? asset = await resolver.resolve(item, source: _source);
      if (asset == null) {
        unresolvedCount += 1;
        continue;
      }

      final NewLibraryViewerCapability capability = _capabilityFromAsset(asset);
      if (guard != null && !guard(capability)) {
        continue;
      }

      final String key = _assetIdentityKey(asset);
      if (!seenAssetKeys.add(key)) {
        continue;
      }

      output.add(_ResolvedAsset(asset: asset, capability: capability));
    }

    if (unresolvedCount > 0 && output.isNotEmpty) {
      _showInfo(context, '$unresolvedCount selected item(s) were skipped.');
    }

    return output;
  }

  String _assetIdentityKey(BaseAsset asset) {
    final String remoteId = asset.remoteId ?? '';
    if (remoteId.isNotEmpty) {
      return 'remote:$remoteId';
    }
    final String localId = asset.localId ?? '';
    if (localId.isNotEmpty) {
      return 'local:$localId';
    }
    return 'hash:${asset.hashCode}';
  }

  Future<T> _runWithTimelineSelection<T>(Iterable<BaseAsset> assets, Future<T> Function() action) async {
    final Set<BaseAsset> selection = assets.toSet();
    final MultiSelectNotifier multiSelect = _ref.read(multiSelectProvider.notifier);
    final MultiSelectState previousState = _ref.read(multiSelectProvider);

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    multiSelect.state = previousState.copyWith(selectedAssets: selection, forceEnable: selection.isNotEmpty);
    try {
      return await action();
    } finally {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      multiSelect.state = previousState;
    }
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

  String _resolveDeleteErrorMessage(BuildContext context, String? error) {
    const prefix = 'i18n:';
    if (error != null && error.startsWith(prefix)) {
      final key = error.substring(prefix.length);
      if (key.isNotEmpty) {
        return key.t(context: context);
      }
    }

    if (error != null && error.trim().isNotEmpty) {
      return error;
    }

    return 'errors.unable_to_delete_assets'.t(context: context);
  }

  String _resolveUploadActionErrorMessage(BuildContext context, String? error) {
    const prefix = 'i18n:';
    if (error != null && error.startsWith(prefix)) {
      final key = error.substring(prefix.length);
      if (key.isNotEmpty) {
        return key.t(context: context);
      }
    }

    if (error != null && error.trim().isNotEmpty) {
      return error;
    }

    return 'errors.unable_to_upload_file'.t(context: context);
  }

  Future<void> _watchManualUploadForbiddenError({required BuildContext context, required String localAssetId}) async {
    final uploadService = _ref.read(uploadServiceProvider);
    TaskStatusUpdate terminalUpdate;
    try {
      terminalUpdate = await uploadService.taskStatusStream
          .where(
            (update) =>
                update.task.group == kManualUploadGroup &&
                update.task.taskId == localAssetId &&
                (update.status == TaskStatus.complete ||
                    update.status == TaskStatus.failed ||
                    update.status == TaskStatus.canceled),
          )
          .first
          .timeout(const Duration(minutes: 10));
    } on TimeoutException {
      return;
    } catch (_) {
      return;
    }

    if (terminalUpdate.status != TaskStatus.failed) {
      return;
    }

    final String? errorKey = _resolveUploadForbiddenErrorKey(terminalUpdate);
    if (errorKey == null) {
      return;
    }

    await _showActionErrorDialog(
      context,
      title: 'errors.unable_to_upload_file'.t(context: context),
      message: errorKey.t(context: context),
    );
  }

  String? _resolveUploadForbiddenErrorKey(TaskStatusUpdate update) {
    final int? statusCode = _extractUploadErrorStatusCode(update);
    if (statusCode != 403) {
      return null;
    }

    final String normalizedMessage = _extractUploadServerMessage(update).toLowerCase();
    if (normalizedMessage.contains('read-only')) {
      return 'errors.upload_error_demo_account_read_only';
    }

    return 'errors.upload_error_forbidden';
  }

  int? _extractUploadErrorStatusCode(TaskStatusUpdate update) {
    final int? responseStatusCode = update.responseStatusCode;
    if (responseStatusCode != null && responseStatusCode > 0) {
      return responseStatusCode;
    }

    final exception = update.exception;
    if (exception is TaskHttpException) {
      final int httpResponseCode = exception.httpResponseCode;
      if (httpResponseCode > 0) {
        return httpResponseCode;
      }
    }

    final dynamic statusCode = _extractUploadErrorBody(update)?['statusCode'];
    if (statusCode is int) {
      return statusCode;
    }
    if (statusCode is String) {
      return int.tryParse(statusCode);
    }

    return null;
  }

  String _extractUploadServerMessage(TaskStatusUpdate update) {
    final dynamic message = _extractUploadErrorBody(update)?['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }

    final exception = update.exception;
    if (exception is TaskHttpException && exception.description.trim().isNotEmpty) {
      return exception.description;
    }

    return update.exception?.description ?? '';
  }

  Map<String, dynamic>? _extractUploadErrorBody(TaskStatusUpdate update) {
    final String? responseBody = update.responseBody;
    if (responseBody != null && responseBody.trim().isNotEmpty) {
      final decoded = _tryJsonDecodeWithEmbeddedObject(responseBody);
      if (decoded != null) {
        return decoded;
      }
    }

    final String? exceptionDescription = update.exception?.description;
    if (exceptionDescription != null && exceptionDescription.trim().isNotEmpty) {
      return _tryJsonDecodeWithEmbeddedObject(exceptionDescription);
    }

    return null;
  }

  Map<String, dynamic>? _tryJsonDecodeWithEmbeddedObject(String raw) {
    final decoded = tryJsonDecode(raw);
    if (decoded != null) {
      return decoded;
    }

    final int jsonStart = raw.indexOf('{');
    final int jsonEnd = raw.lastIndexOf('}');
    if (jsonStart == -1 || jsonEnd <= jsonStart) {
      return null;
    }

    return tryJsonDecode(raw.substring(jsonStart, jsonEnd + 1));
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

  Future<void> _showActionErrorDialog(BuildContext context, {required String title, required String message}) async {
    if (!context.mounted) {
      return;
    }

    final normalizedMessage = message.trim().isNotEmpty ? message : title;

    await showPlatformDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(normalizedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
            ),
          ],
        );
      },
    );
  }
}

class _ResolvedAsset {
  const _ResolvedAsset({required this.asset, required this.capability});

  final BaseAsset asset;
  final NewLibraryViewerCapability capability;
}

class _UserVisibleActionError implements Exception {
  const _UserVisibleActionError(this.message);

  final String message;

  @override
  String toString() => message;
}
