import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_viewer_action_runner.dart';
import 'package:immich_mobile/presentation/pages/pizcloud/new_library_viewer_actions.dart';
import 'package:immich_mobile/providers/pizcloud/new_library.provider.dart';
import 'package:immich_mobile/widgets/common/immich_sliver_app_bar.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

@RoutePage()
class NewLibraryPage extends ConsumerWidget {
  const NewLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(newLibraryGallerySourceProvider);
    final reselectSignal = ref.watch(newLibraryReselectSignalProvider);
    final runner = NewLibraryViewerActionRunner(ref: ref, source: source);
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
