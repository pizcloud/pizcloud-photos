import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/setting.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_viewer_action_runner.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_viewer_actions.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_viewer_capability.dart';
import 'package:immich_mobile/providers/infrastructure/setting.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/pizcloud/new_library.provider.dart';
import 'package:immich_mobile/widgets/common/drag_sheet.dart';
import 'package:immich_mobile/widgets/common/immich_sliver_app_bar.dart';
// import 'package:intl/intl.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

@RoutePage()
class NewLibraryPage extends HookConsumerWidget {
  const NewLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(newLibraryGallerySourceProvider);
    final reselectSignal = ref.watch(newLibraryReselectSignalProvider);
    final groupBy = ref.watch(timelineFactoryProvider).groupBy;
    final runner = NewLibraryViewerActionRunner(ref: ref, source: source);
    final showStorageIndicator = ref.watch(settingsProvider.select((s) => s.get(Setting.showStorageIndicator)));
    final String localeTag = Localizations.localeOf(context).toLanguageTag();

    final ValueNotifier<List<MediaItem>> selectedItemsState = useState<List<MediaItem>>(const <MediaItem>[]);
    final ValueNotifier<int> clearSelectionSignal = useState<int>(0);
    final ValueNotifier<bool> isActionProcessing = useState<bool>(false);
    final NewLibraryLocateRequest? pendingLocateRequest = ref.watch(newLibraryLocateRequestProvider);

    final List<MediaItem> selectedItems = selectedItemsState.value;
    final _SelectionActionVisibility selectionVisibility = _SelectionActionVisibility.fromSelection(
      selectedItems,
      runner: runner,
    );

    Future<void> runSelectionAction(Future<bool> Function() action) async {
      if (isActionProcessing.value) {
        return;
      }
      isActionProcessing.value = true;
      try {
        final bool shouldClearSelection = await action();
        if (!context.mounted) {
          return;
        }
        if (shouldClearSelection) {
          clearSelectionSignal.value += 1;
          selectedItemsState.value = const <MediaItem>[];
        }
      } finally {
        if (context.mounted) {
          isActionProcessing.value = false;
        }
      }
    }

    void syncSelectedItemsFromGallery(List<MediaItem> items) {
      final List<MediaItem> nextItems = List<MediaItem>.unmodifiable(items);

      void applySelection() {
        if (context.mounted == false) {
          return;
        }
        selectedItemsState.value = nextItems;
      }

      // Avoid Hook setState while a build is in progress.
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) => applySelection());
        return;
      }

      applySelection();
    }

    String? buildDateOverlayLabel(MediaItem item) {
      final DateTime? sourceDate = item.createdAt ?? item.addedAt;
      if (sourceDate == null) {
        return null;
      }
      final DateTime date = sourceDate.toLocal();
      if (groupBy == GroupAssetsBy.month) {
        final DateFormat monthFormatter = date.year == DateTime.now().year
            ? DateFormat.MMMM(localeTag)
            : DateFormat.yMMMM(localeTag);
        return monthFormatter.format(date);
      }
      return DateFormat.yMMMEd(localeTag).format(date);
    }

    final GallerySortFilterMenuTexts sortFilterMenuTexts = GallerySortFilterMenuTexts(
      tooltipSortFilter: 'new_library_sort_filter_tooltip'.tr(),
      sectionSort: 'new_library_sort_section'.tr(),
      optionCreatedTime: 'new_library_sort_created_time'.tr(),
      optionAddedTime: 'new_library_sort_added_time'.tr(),
      sectionFilter: 'filter'.tr(),
      optionShowAll: 'new_library_show_all'.tr(),
      sectionMediaType: 'media_type'.tr(),
      optionPhotos: 'photos'.tr(),
      optionVideos: 'videos'.tr(),
      sectionStorage: 'new_library_storage_section'.tr(),
      optionOnDevice: 'on_this_device'.tr(),
      optionCloud: 'new_library_cloud'.tr(),
    );
    final GalleryDateBrowseTexts dateBrowseTexts = GalleryDateBrowseTexts(
      optionAll: 'new_library_browse_all'.tr(),
      optionYear: 'new_library_browse_year'.tr(),
      optionMonth: 'new_library_browse_month'.tr(),
    );

    final gallery = PizGallery(
      source: source,
      scrollToTopSignal: reselectSignal,
      onViewerShareRequested: (item) => runner.onShareRequested(item, context),
      onViewerDeleteRequested: (item) => runner.onDeleteRequested(item, context),
      onViewerEditRequested: (item) => runner.editImage(item, context),
      onViewerUploadRequested: (item) => runner.upload(item, context),
      onViewerAddToAlbumRequested: (item) => runner.addToAlbum(item, context),
      viewerActions: buildNewLibraryViewerActions(runner: runner),
      includeDefaultViewerActions: false,
      canDeleteItem: runner.canDeleteItemSync,
      canEditItem: runner.canEditImageSync,
      canUploadItem: runner.canUploadItemSync,
      canAddToAlbumItem: runner.canAddToAlbumSync,
      showDateOverlay: true,
      dateOverlayTextBuilder: buildDateOverlayLabel,
      sortFilterMenuTexts: sortFilterMenuTexts,
      showDateBrowseOverlay: true,
      dateBrowseTexts: dateBrowseTexts,
      showStorageIndicator: showStorageIndicator,
      showScrollbarDateHint: true,
      locateItemId: pendingLocateRequest?.mediaItemId,
      locateItemSignal: pendingLocateRequest?.requestId ?? 0,
      onLocateHandled: (requestId) {
        ref.read(newLibraryLocateRequestProvider.notifier).clearIfMatches(requestId);
      },
      enableMultiSelect: true,
      showSelectModeButton: true,
      clearSelectionSignal: clearSelectionSignal.value,
      onSelectionChanged: (items) {
        // selectedItemsState.value = List<MediaItem>.unmodifiable(items);
        syncSelectedItemsFromGallery(items);
      },
      storageIndicatorResolver: (item) {
        final BaseAsset? asset = source.findAssetByMediaItemId(item.id);
        if (asset != null) {
          return switch (asset.storage) {
            AssetState.local => GridStorageIndicatorState.local,
            AssetState.remote => GridStorageIndicatorState.remote,
            AssetState.merged => GridStorageIndicatorState.merged,
          };
        }

        // inferred from sourceType only.
        return switch (item.sourceType) {
          MediaSourceType.local => GridStorageIndicatorState.local,
          MediaSourceType.remote => GridStorageIndicatorState.remote,
        };
      },
    );

    return CustomScrollView(
      // return SizedBox.expand(child: PizGallery(...));
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        const ImmichSliverAppBar(floating: false, pinned: true, snap: false),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverFillRemaining(
          hasScrollBody: true,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: gallery),
              if (selectedItems.isNotEmpty)
                _NewLibraryActionBar(
                  isProcessing: isActionProcessing.value,
                  visibility: selectionVisibility,
                  selectedCount: selectedItems.length,
                  onClose: () {
                    clearSelectionSignal.value += 1;
                    selectedItemsState.value = const <MediaItem>[];
                  },
                  onShare: () => runSelectionAction(() => runner.shareMany(selectedItems, context)),
                  onAddToAlbum: () => runSelectionAction(() => runner.addToAlbumMany(selectedItems, context)),
                  onUpload: () => runSelectionAction(() => runner.uploadMany(selectedItems, context)),
                  onDownload: () => runSelectionAction(() => runner.downloadMany(selectedItems, context)),
                  onDelete: () => runSelectionAction(() => runner.deleteMany(selectedItems, context)),
                  onDeleteLocal: () => runSelectionAction(() => runner.deleteLocalMany(selectedItems, context)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // Old integration hooks were intentionally no-op:
  // Future<void> _onViewerShareRequested(MediaItem item) async {}
  // Future<void> _onViewerDeleteRequested(MediaItem item) async {}
}

class _SelectionActionVisibility {
  const _SelectionActionVisibility({
    required this.showAddToAlbum,
    required this.showUpload,
    required this.showDownload,
    required this.showDelete,
    required this.showDeleteLocal,
  });

  final bool showAddToAlbum;
  final bool showUpload;
  final bool showDownload;
  final bool showDelete;
  final bool showDeleteLocal;

  factory _SelectionActionVisibility.fromSelection(
    List<MediaItem> items, {
    required NewLibraryViewerActionRunner runner,
  }) {
    bool showAddToAlbum = false;
    bool showUpload = false;
    bool showDownload = false;
    bool showDelete = false;
    bool showDeleteLocal = false;

    for (final MediaItem item in items) {
      final NewLibraryViewerCapability capability = runner.capabilityForItemSync(item);
      showAddToAlbum = showAddToAlbum || capability.canAddToAlbum;
      showUpload = showUpload || capability.canUpload;
      showDownload = showDownload || capability.canDownload;
      showDelete = showDelete || capability.canDeleteRemoteAndLocal;
      showDeleteLocal = showDeleteLocal || capability.canDeleteLocal;
    }

    return _SelectionActionVisibility(
      showAddToAlbum: showAddToAlbum,
      showUpload: showUpload,
      showDownload: showDownload,
      showDelete: showDelete,
      showDeleteLocal: showDeleteLocal,
    );
  }
}

class _NewLibraryActionBar extends StatelessWidget {
  const _NewLibraryActionBar({
    required this.isProcessing,
    required this.visibility,
    required this.selectedCount,
    required this.onClose,
    required this.onShare,
    required this.onAddToAlbum,
    required this.onUpload,
    required this.onDownload,
    required this.onDelete,
    required this.onDeleteLocal,
  });

  final bool isProcessing;
  final _SelectionActionVisibility visibility;
  final int selectedCount;
  final VoidCallback onClose;
  final VoidCallback onShare;
  final VoidCallback onAddToAlbum;
  final VoidCallback onUpload;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onDeleteLocal;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String selectedLabel = 'Selected $selectedCount';
    const double compactBarHeight = 136;
    final bool isDarkMode = colorScheme.brightness == Brightness.dark;
    final Color overlayColor = colorScheme.surface.withValues(alpha: isDarkMode ? 0.95 : 0.96);
    final Color overlayShadowColor = Colors.black.withValues(alpha: isDarkMode ? 0.34 : 0.20);
    final Color overlayBorderColor = colorScheme.outlineVariant.withValues(alpha: isDarkMode ? 0.38 : 0.26);

    final List<Widget> buttons = <Widget>[
      ControlBoxButton(iconData: Icons.share_rounded, label: 'share'.tr(), onPressed: isProcessing ? null : onShare),
      if (visibility.showAddToAlbum)
        ControlBoxButton(
          iconData: Icons.photo_album_outlined,
          label: 'add_to_album'.tr(),
          onPressed: isProcessing ? null : onAddToAlbum,
        ),
      if (visibility.showUpload)
        ControlBoxButton(
          iconData: Icons.backup_outlined,
          label: 'upload'.tr(),
          onPressed: isProcessing ? null : onUpload,
        ),
      if (visibility.showDownload)
        ControlBoxButton(
          iconData: Icons.download_rounded,
          label: 'download'.tr(),
          onPressed: isProcessing ? null : onDownload,
        ),
      if (visibility.showDelete)
        ControlBoxButton(
          iconData: Icons.delete_sweep_outlined,
          label: 'delete'.tr(),
          onPressed: isProcessing ? null : onDelete,
        ),
      if (visibility.showDeleteLocal)
        ControlBoxButton(
          iconData: Icons.no_cell_outlined,
          label: 'control_bottom_app_bar_delete_from_local'.tr(),
          onPressed: isProcessing ? null : onDeleteLocal,
        ),
    ];

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Card(
          margin: EdgeInsets.zero,
          color: overlayColor,
          surfaceTintColor: Colors.transparent,
          shadowColor: overlayShadowColor,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            side: BorderSide(color: overlayBorderColor, width: 0.8),
          ),
          elevation: 6,
          child: SizedBox(
            height: compactBarHeight,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 2, 2),
                  child: Row(
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.36), width: 1),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                selectedLabel,
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'close'.tr(),
                        onPressed: isProcessing ? null : onClose,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 0.8, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    children: buttons,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
