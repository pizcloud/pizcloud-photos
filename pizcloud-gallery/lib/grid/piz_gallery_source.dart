import 'dart:async';

import 'media_item.dart';

/// Data contract for feeding media into [PizGallery].
///
/// Extend this in host apps/packages, then pass the source to gallery.
abstract class PizGallerySource {
  /// Loads the initial full snapshot shown by the gallery.
  Future<List<MediaItem>> loadInitial();

  /// Optional live updates stream.
  ///
  /// Return `null` if source is snapshot-only.
  Stream<List<MediaItem>>? watchUpdates() => null;

  /// Optional cleanup hook for source resources.
  Future<void> dispose() async {}

  /// Optional mutation hook used by viewer/grid delete actions.
  ///
  /// Implementations can ignore this if the source is immutable.
  Future<void> removeItem(MediaItem item) async {}
}
