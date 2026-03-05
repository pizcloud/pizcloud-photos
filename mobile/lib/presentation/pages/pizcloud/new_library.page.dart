import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
    final gallery = PizGallery(
      source: source,
      scrollToTopSignal: reselectSignal,
      onViewerShareRequested: _onViewerShareRequested,
      onViewerDeleteRequested: _onViewerDeleteRequested,
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

  Future<void> _onViewerShareRequested(MediaItem item) async {
    // Intentionally no-op for the first integration.
  }

  Future<void> _onViewerDeleteRequested(MediaItem item) async {
    // Intentionally no-op for the first integration.
  }
}
