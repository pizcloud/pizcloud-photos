import 'dart:async';

import '../media_item.dart';
import '../piz_gallery_source.dart';

/// Mutable in-memory source used for test/demo/manual feeds.
class InMemoryGallerySource extends PizGallerySource {
  InMemoryGallerySource({
    Iterable<MediaItem> initialItems = const <MediaItem>[],
  }) : _items = List<MediaItem>.unmodifiable(initialItems);

  final StreamController<List<MediaItem>> _controller =
      StreamController<List<MediaItem>>.broadcast();
  List<MediaItem> _items;
  bool _disposed = false;

  @override
  Future<List<MediaItem>> loadInitial() async => _items;

  @override
  Stream<List<MediaItem>> watchUpdates() => _controller.stream;

  void replaceAll(Iterable<MediaItem> items, {bool emitUpdate = true}) {
    if (_disposed) return;
    _items = List<MediaItem>.unmodifiable(items);
    if (emitUpdate) {
      _controller.add(_items);
    }
  }

  void append(Iterable<MediaItem> items, {bool emitUpdate = true}) {
    if (_disposed) return;
    if (items.isEmpty) return;
    _items = List<MediaItem>.unmodifiable(<MediaItem>[..._items, ...items]);
    if (emitUpdate) {
      _controller.add(_items);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }
}
