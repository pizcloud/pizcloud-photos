import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/pizcloud/new_library.provider.dart';
import 'package:pizcloud_gallery/pizcloud_gallery.dart';

@RoutePage()
class NewLibraryPage extends ConsumerWidget {
  const NewLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(newLibraryGallerySourceProvider);
    final reselectSignal = ref.watch(newLibraryReselectSignalProvider);

    return SizedBox.expand(
      child: PizGallery(
        source: source,
        scrollToTopSignal: reselectSignal,
        onViewerShareRequested: _onViewerShareRequested,
        onViewerDeleteRequested: _onViewerDeleteRequested,
      ),
    );
  }

  Future<void> _onViewerShareRequested(MediaItem item) async {
    // Intentionally no-op for the first integration.
  }

  Future<void> _onViewerDeleteRequested(MediaItem item) async {
    // Intentionally no-op for the first integration.
  }
}
