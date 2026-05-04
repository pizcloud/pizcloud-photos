import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';

import 'viewer_action.dart'; // new
import 'viewer_quick_actions_texts.dart'; // new

typedef ViewerDeleteCallback = FutureOr<void> Function(MediaItem item);
typedef ViewerShareCallback = FutureOr<void> Function(MediaItem item);
// new
typedef ViewerEditCallback = FutureOr<void> Function(MediaItem item);
typedef ViewerUploadCallback = FutureOr<void> Function(MediaItem item);
typedef ViewerAddToAlbumCallback = FutureOr<void> Function(MediaItem item);
typedef ViewerCanDeleteItemCallback = bool Function(MediaItem item); // new
typedef ViewerCanEditItemCallback = bool Function(MediaItem item);
typedef ViewerCanUploadItemCallback = bool Function(MediaItem item);
typedef ViewerCanAddToAlbumItemCallback = bool Function(MediaItem item);
// #new

class ViewerSession {
  const ViewerSession({
    required this.items,
    required this.initialIndex,
    this.initialOriginalReady = false,
    this.initialHeroTag,
    this.initialThumbUrl, // new
    this.initialThumbBytes, // new
    this.onVisibleIndexChanged,
    this.onShareRequested,
    this.onDeleteRequested,
    this.onEditRequested, // new
    this.onUploadRequested, // new
    this.onAddToAlbumRequested, // new
    // new
    this.viewerActions,
    this.includeDefaultViewerActions = true,
    this.canDeleteItem,
    this.canEditItem,
    this.canUploadItem,
    this.canAddToAlbumItem,
    this.quickActionsTexts = const ViewerQuickActionsTexts.defaults(),
    // #new
  });

  final List<MediaItem> items;
  final int initialIndex;
  final bool initialOriginalReady;
  final String? initialHeroTag;
  final String? initialThumbUrl; // new
  final Uint8List? initialThumbBytes; // new
  final ValueChanged<int>? onVisibleIndexChanged;
  final ViewerShareCallback? onShareRequested;
  final ViewerDeleteCallback? onDeleteRequested;
  final ViewerEditCallback? onEditRequested; // new
  final ViewerUploadCallback? onUploadRequested; // new
  final ViewerAddToAlbumCallback? onAddToAlbumRequested; // new
  // new
  final List<ViewerAction>? viewerActions;
  final bool includeDefaultViewerActions;
  final ViewerCanDeleteItemCallback? canDeleteItem;
  final ViewerCanEditItemCallback? canEditItem;
  final ViewerCanUploadItemCallback? canUploadItem;
  final ViewerCanAddToAlbumItemCallback? canAddToAlbumItem;
  final ViewerQuickActionsTexts quickActionsTexts;
  // #new

  bool get isEmpty => items.isEmpty;

  int get clampedInitialIndex {
    if (items.isEmpty) return 0;
    return initialIndex.clamp(0, items.length - 1);
  }
}
