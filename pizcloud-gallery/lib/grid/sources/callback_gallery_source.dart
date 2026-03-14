import 'dart:async';

import '../media_item.dart';
import '../piz_gallery_source.dart';

typedef GalleryItemsLoader = Future<List<MediaItem>> Function();
typedef GalleryItemsWatchBuilder = Stream<List<MediaItem>> Function();
typedef GalleryDisposeCallback = FutureOr<void> Function();

/// Generic adapter when host app already has its own local/remote loaders.
class CallbackGallerySource extends PizGallerySource {
  CallbackGallerySource({
    required GalleryItemsLoader loadInitial,
    GalleryItemsWatchBuilder? watchUpdates,
    GalleryDisposeCallback? onDispose,
  }) : _loadInitial = loadInitial,
       _watchUpdates = watchUpdates,
       _onDispose = onDispose;

  final GalleryItemsLoader _loadInitial;
  final GalleryItemsWatchBuilder? _watchUpdates;
  final GalleryDisposeCallback? _onDispose;

  @override
  Future<List<MediaItem>> loadInitial() => _loadInitial();

  @override
  Stream<List<MediaItem>>? watchUpdates() => _watchUpdates?.call();

  @override
  Future<void> dispose() async {
    await _onDispose?.call();
  }
}

/// Semantic alias for callback sources backed by a remote service.
class RemoteGallerySource extends CallbackGallerySource {
  RemoteGallerySource({
    required super.loadInitial,
    super.watchUpdates,
    super.onDispose,
  });
}

/// Semantic alias for callback sources backed by local storage/device media.
class LocalGallerySource extends CallbackGallerySource {
  LocalGallerySource({
    required super.loadInitial,
    super.watchUpdates,
    super.onDispose,
  });
}
