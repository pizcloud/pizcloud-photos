import 'dart:async';
import 'dart:collection';

import '../media_item.dart';
import '../piz_gallery_source.dart';

enum HybridMergePriority { localFirst, remoteFirst }

/// Combines local and remote sources into one merged feed.
class HybridGallerySource extends PizGallerySource {
  HybridGallerySource({
    required this.local,
    required this.remote,
    this.priority = HybridMergePriority.localFirst,
    this.deduplicateById = true,
    this.disposeChildren = true,
  });

  final PizGallerySource local;
  final PizGallerySource remote;
  final HybridMergePriority priority;
  final bool deduplicateById;
  final bool disposeChildren;

  StreamController<List<MediaItem>>? _updatesController;
  StreamSubscription<List<MediaItem>>? _localSubscription;
  StreamSubscription<List<MediaItem>>? _remoteSubscription;
  List<MediaItem> _latestLocal = const <MediaItem>[];
  List<MediaItem> _latestRemote = const <MediaItem>[];
  bool _disposed = false;

  @override
  Future<List<MediaItem>> loadInitial() async {
    final List<List<MediaItem>> snapshots = await Future.wait<List<MediaItem>>([
      local.loadInitial(),
      remote.loadInitial(),
    ]);
    _latestLocal = List<MediaItem>.unmodifiable(snapshots[0]);
    _latestRemote = List<MediaItem>.unmodifiable(snapshots[1]);
    return _merge(_latestLocal, _latestRemote);
  }

  @override
  Stream<List<MediaItem>>? watchUpdates() {
    if (_disposed) return null;
    final Stream<List<MediaItem>>? localUpdates = local.watchUpdates();
    final Stream<List<MediaItem>>? remoteUpdates = remote.watchUpdates();
    if (localUpdates == null && remoteUpdates == null) {
      return null;
    }
    _updatesController ??= StreamController<List<MediaItem>>.broadcast(
      onListen: () => _attachListeners(localUpdates, remoteUpdates),
      onCancel: _detachListenersIfUnused,
    );
    return _updatesController!.stream;
  }

  void _attachListeners(
    Stream<List<MediaItem>>? localUpdates,
    Stream<List<MediaItem>>? remoteUpdates,
  ) {
    if (_localSubscription == null && localUpdates != null) {
      _localSubscription = localUpdates.listen((List<MediaItem> items) {
        _latestLocal = List<MediaItem>.unmodifiable(items);
        _emitMerged();
      }, onError: _updatesController?.addError);
    }
    if (_remoteSubscription == null && remoteUpdates != null) {
      _remoteSubscription = remoteUpdates.listen((List<MediaItem> items) {
        _latestRemote = List<MediaItem>.unmodifiable(items);
        _emitMerged();
      }, onError: _updatesController?.addError);
    }
  }

  Future<void> _detachListenersIfUnused() async {
    final StreamController<List<MediaItem>>? controller = _updatesController;
    if (controller == null || controller.hasListener) {
      return;
    }
    await _localSubscription?.cancel();
    await _remoteSubscription?.cancel();
    _localSubscription = null;
    _remoteSubscription = null;
  }

  void _emitMerged() {
    final StreamController<List<MediaItem>>? controller = _updatesController;
    if (controller == null || controller.isClosed) {
      return;
    }
    controller.add(_merge(_latestLocal, _latestRemote));
  }

  List<MediaItem> _merge(
    List<MediaItem> localItems,
    List<MediaItem> remoteItems,
  ) {
    if (!deduplicateById) {
      return switch (priority) {
        HybridMergePriority.localFirst => List<MediaItem>.unmodifiable([
          ...localItems,
          ...remoteItems,
        ]),
        HybridMergePriority.remoteFirst => List<MediaItem>.unmodifiable([
          ...remoteItems,
          ...localItems,
        ]),
      };
    }

    final LinkedHashMap<String, MediaItem> byId =
        LinkedHashMap<String, MediaItem>();
    final List<MediaItem> ordered = switch (priority) {
      HybridMergePriority.localFirst => <MediaItem>[
        ...localItems,
        ...remoteItems,
      ],
      HybridMergePriority.remoteFirst => <MediaItem>[
        ...remoteItems,
        ...localItems,
      ],
    };
    for (final MediaItem item in ordered) {
      byId.putIfAbsent(item.id, () => item);
    }
    return List<MediaItem>.unmodifiable(byId.values);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _localSubscription?.cancel();
    await _remoteSubscription?.cancel();
    _localSubscription = null;
    _remoteSubscription = null;
    await _updatesController?.close();
    _updatesController = null;
    if (disposeChildren) {
      await local.dispose();
      await remote.dispose();
    }
  }

  @override
  Future<void> removeItem(MediaItem item) async {
    if (_disposed) {
      return;
    }
    _latestLocal = List<MediaItem>.unmodifiable(
      _latestLocal.where((MediaItem value) => value.id != item.id),
    );
    _latestRemote = List<MediaItem>.unmodifiable(
      _latestRemote.where((MediaItem value) => value.id != item.id),
    );
    await Future.wait<void>(<Future<void>>[
      local.removeItem(item),
      remote.removeItem(item),
    ]);
    _emitMerged();
  }
}
