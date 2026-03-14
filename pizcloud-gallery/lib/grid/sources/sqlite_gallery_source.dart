import 'dart:async';
import 'dart:collection';

import '../media_item.dart';
import '../piz_gallery_source.dart';

typedef SqliteRowsLoader<Row> = Future<List<Row>> Function();
typedef SqliteRowsWatcher<Row> = Stream<List<Row>> Function();
typedef SqliteRowToMediaItem<Row> = MediaItem Function(Row row);
typedef SqliteSourceDispose = FutureOr<void> Function();

/// Generic SQLite-backed gallery source adapter.
///
/// Host app owns query logic and row model, then maps each row to [MediaItem].
class SqliteGallerySource<Row> extends PizGallerySource {
  SqliteGallerySource({
    required SqliteRowsLoader<Row> loadRows,
    required SqliteRowToMediaItem<Row> mapRowToItem,
    SqliteRowsWatcher<Row>? watchRows,
    SqliteSourceDispose? onDispose,
    this.deduplicateById = true,
    this.skipUpdatesWithSameIds = true,
  }) : _loadRows = loadRows,
       _mapRowToItem = mapRowToItem,
       _watchRows = watchRows,
       _onDispose = onDispose;

  final SqliteRowsLoader<Row> _loadRows;
  final SqliteRowToMediaItem<Row> _mapRowToItem;
  final SqliteRowsWatcher<Row>? _watchRows;
  final SqliteSourceDispose? _onDispose;
  final bool deduplicateById;
  final bool skipUpdatesWithSameIds;

  bool _disposed = false;

  @override
  Future<List<MediaItem>> loadInitial() async {
    if (_disposed) {
      return const <MediaItem>[];
    }
    final List<Row> rows = await _loadRows();
    return _mapAndNormalize(rows);
  }

  @override
  Stream<List<MediaItem>>? watchUpdates() {
    if (_disposed) {
      return null;
    }
    final SqliteRowsWatcher<Row>? watchRows = _watchRows;
    if (watchRows == null) {
      return null;
    }
    Stream<List<MediaItem>> stream = watchRows().map(_mapAndNormalize);
    if (skipUpdatesWithSameIds) {
      stream = stream.transform(_distinctByIdsTransformer());
    }
    return stream;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _onDispose?.call();
  }

  List<MediaItem> _mapAndNormalize(List<Row> rows) {
    final List<MediaItem> mapped = rows
        .map(_mapRowToItem)
        .toList(growable: false);
    if (!deduplicateById) {
      return List<MediaItem>.unmodifiable(mapped);
    }
    final LinkedHashMap<String, MediaItem> byId =
        LinkedHashMap<String, MediaItem>();
    for (final MediaItem item in mapped) {
      byId.putIfAbsent(item.id, () => item);
    }
    return List<MediaItem>.unmodifiable(byId.values);
  }

  StreamTransformer<List<MediaItem>, List<MediaItem>>
  _distinctByIdsTransformer() {
    List<String>? lastIds;
    return StreamTransformer<List<MediaItem>, List<MediaItem>>.fromHandlers(
      handleData: (List<MediaItem> items, EventSink<List<MediaItem>> sink) {
        final List<String> nextIds = items
            .map((MediaItem item) => item.id)
            .toList(growable: false);
        if (lastIds != null && _sameIds(lastIds!, nextIds)) {
          return;
        }
        lastIds = nextIds;
        sink.add(items);
      },
    );
  }

  bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}
