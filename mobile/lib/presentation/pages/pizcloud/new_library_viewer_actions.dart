import 'package:flutter/material.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

import 'new_library_viewer_action_runner.dart';

List<ViewerAction> buildNewLibraryViewerActions({required NewLibraryViewerActionRunner runner}) {
  return <ViewerAction>[
    _RunnerViewerAction(
      id: 'new_library_view_in_timeline',
      label: 'View in timeline',
      icon: Icons.image_search_rounded,
      isVisible: (item) => runner.capabilityForItemSync(item).canViewInTimeline,
      onExecute: (actionContext, item) => runner.viewInTimeline(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_add_to_album',
      label: 'Add to album',
      icon: Icons.photo_album_outlined,
      isVisible: (item) => runner.capabilityForItemSync(item).canAddToAlbum,
      onExecute: (actionContext, item) => runner.addToAlbum(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_favorite',
      label: 'Favorite',
      icon: Icons.favorite_border_rounded,
      isVisible: (item) => runner.capabilityForItemSync(item).canFavorite,
      onExecute: (actionContext, item) => runner.favorite(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_unfavorite',
      label: 'Unfavorite',
      icon: Icons.favorite_rounded,
      isVisible: (item) => runner.capabilityForItemSync(item).canUnfavorite,
      onExecute: (actionContext, item) => runner.unfavorite(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_archive',
      label: 'Archive',
      icon: Icons.archive_outlined,
      isVisible: (item) => runner.capabilityForItemSync(item).canArchive,
      onExecute: (actionContext, item) => runner.archive(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_unarchive',
      label: 'Unarchive',
      icon: Icons.unarchive_outlined,
      isVisible: (item) => runner.capabilityForItemSync(item).canUnarchive,
      onExecute: (actionContext, item) => runner.unarchive(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_move_to_lock_folder',
      label: 'Move to locked folder',
      icon: Icons.lock_outline_rounded,
      isVisible: (item) => runner.capabilityForItemSync(item).canMoveToLockFolder,
      onExecute: (actionContext, item) => runner.moveToLockFolder(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_remove_from_lock_folder',
      label: 'Remove from locked folder',
      icon: Icons.lock_open_rounded,
      isVisible: (item) => runner.capabilityForItemSync(item).canRemoveFromLockFolder,
      onExecute: (actionContext, item) => runner.removeFromLockFolder(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_share_link',
      label: 'Share link',
      icon: Icons.link_rounded,
      isVisible: (item) => runner.capabilityForItemSync(item).canShareLink,
      onExecute: (actionContext, item) => runner.shareLink(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_download',
      label: 'Download',
      icon: Icons.download_rounded,
      isVisible: (item) => runner.capabilityForItemSync(item).canDownload,
      onExecute: (actionContext, item) => runner.download(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_upload',
      label: 'Upload',
      icon: Icons.backup_outlined,
      isVisible: (item) => runner.capabilityForItemSync(item).canUpload,
      onExecute: (actionContext, item) => runner.upload(item, actionContext.context),
    ),
    _RunnerViewerAction(
      id: 'new_library_delete_local',
      label: 'Delete local copy',
      icon: Icons.no_cell_outlined,
      isVisible: (item) => runner.capabilityForItemSync(item).canDeleteLocal,
      onExecute: (actionContext, item) => runner.deleteLocal(item, actionContext.context),
    ),
    const ShowImageInfoAction(),
    const CopyImageUrlAction(),
  ];
}

class _RunnerViewerAction extends ViewerAction {
  const _RunnerViewerAction({
    required this.id,
    required this.label,
    required this.icon,
    required bool Function(MediaItem item) isVisible,
    required Future<void> Function(ViewerActionContext, MediaItem) onExecute,
  }) : _isVisible = isVisible,
       _onExecute = onExecute;

  @override
  final String id;

  @override
  final String label;

  @override
  final IconData icon;

  final bool Function(MediaItem item) _isVisible;
  final Future<void> Function(ViewerActionContext, MediaItem) _onExecute;

  @override
  bool isVisible(MediaItem item) => _isVisible(item);

  @override
  Future<void> execute(ViewerActionContext context, MediaItem item) async {
    await _onExecute(context, item);
  }
}
