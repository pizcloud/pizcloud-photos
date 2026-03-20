import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/setting.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_viewer_action_runner.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_viewer_actions.dart';
import 'package:immich_mobile/providers/infrastructure/setting.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/pizcloud/new_library.provider.dart';
import 'package:immich_mobile/widgets/common/immich_sliver_app_bar.dart';
// import 'package:intl/intl.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

@RoutePage()
class NewLibraryPage extends ConsumerWidget {
  const NewLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(newLibraryGallerySourceProvider);
    final reselectSignal = ref.watch(newLibraryReselectSignalProvider);
    final groupBy = ref.watch(timelineFactoryProvider).groupBy;
    final runner = NewLibraryViewerActionRunner(ref: ref, source: source);
    final showStorageIndicator = ref.watch(settingsProvider.select((s) => s.get(Setting.showStorageIndicator)));
    final String localeTag = Localizations.localeOf(context).toLanguageTag();

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
        SliverFillRemaining(hasScrollBody: true, child: gallery),
      ],
    );
  }

  // Old integration hooks were intentionally no-op:
  // Future<void> _onViewerShareRequested(MediaItem item) async {}
  // Future<void> _onViewerDeleteRequested(MediaItem item) async {}
}
