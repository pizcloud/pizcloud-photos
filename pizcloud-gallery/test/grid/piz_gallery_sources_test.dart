import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pizcloud_gallery/grid/piz_gallery.dart';
import 'package:pizcloud_gallery/grid/piz_gallery_testing.dart';

void main() {
  group('InMemoryGallerySource', () {
    test('returns initial snapshot and emits replacement updates', () async {
      final InMemoryGallerySource source = InMemoryGallerySource(
        initialItems: <MediaItem>[_item('1')],
      );

      final List<MediaItem> initial = await source.loadInitial();
      expect(initial.map((item) => item.id).toList(), <String>['1']);

      final List<List<MediaItem>> updates = <List<MediaItem>>[];
      final subscription = source.watchUpdates().listen(updates.add);
      source.replaceAll(<MediaItem>[_item('2'), _item('3')]);
      await Future<void>.delayed(Duration.zero);

      expect(updates, hasLength(1));
      expect(updates.first.map((item) => item.id).toList(), <String>['2', '3']);

      await subscription.cancel();
      await source.dispose();
    });
  });

  group('HybridGallerySource', () {
    test('merges local + remote and keeps local precedence by id', () async {
      final InMemoryGallerySource local = InMemoryGallerySource(
        initialItems: <MediaItem>[
          _item('same', sourceType: MediaSourceType.local),
          _item('local-only', sourceType: MediaSourceType.local),
        ],
      );
      final InMemoryGallerySource remote = InMemoryGallerySource(
        initialItems: <MediaItem>[
          _item('same', sourceType: MediaSourceType.remote),
          _item('remote-only', sourceType: MediaSourceType.remote),
        ],
      );
      final HybridGallerySource source = HybridGallerySource(
        local: local,
        remote: remote,
      );

      final List<MediaItem> initial = await source.loadInitial();
      expect(initial.map((item) => item.id).toList(), <String>[
        'same',
        'local-only',
        'remote-only',
      ]);
      expect(initial.first.sourceType, MediaSourceType.local);

      final List<List<MediaItem>> updates = <List<MediaItem>>[];
      final Stream<List<MediaItem>>? stream = source.watchUpdates();
      expect(stream, isNotNull);
      final subscription = stream!.listen(updates.add);
      local.replaceAll(<MediaItem>[_item('local-updated')]);
      await Future<void>.delayed(Duration.zero);

      expect(updates, hasLength(1));
      expect(updates.first.map((item) => item.id).toList(), <String>[
        'local-updated',
        'same',
        'remote-only',
      ]);

      await subscription.cancel();
      await source.dispose();
    });
  });

  group('JsonAssetGallerySource', () {
    test('loads media items from injected asset bundle', () async {
      final JsonAssetGallerySource source = JsonAssetGallerySource(
        assetPath: 'mock/sample.json',
        bundle: _MapAssetBundle(<String, String>{
          'mock/sample.json': jsonEncode(<Map<String, Object?>>[
            _item('a').toJson(),
            _item('b').toJson(),
          ]),
        }),
        limit: 1,
      );

      final List<MediaItem> items = await source.loadInitial();
      expect(items, hasLength(1));
      expect(items.first.id, 'a');
    });
  });
}

MediaItem _item(
  String id, {
  MediaSourceType sourceType = MediaSourceType.remote,
}) {
  return MediaItem(
    id: id,
    type: MediaType.photo,
    sourceType: sourceType,
    originalUrl: 'https://example.com/$id.jpg',
    thumbnails: MediaThumbnails(
      size100: 'https://example.com/$id-100.jpg',
      size300: 'https://example.com/$id-300.jpg',
      size600: 'https://example.com/$id-600.jpg',
    ),
  );
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final String? value = _assets[key];
    if (value == null) {
      throw StateError('Missing asset: $key');
    }
    final Uint8List bytes = Uint8List.fromList(utf8.encode(value));
    return ByteData.view(bytes.buffer);
  }
}
