import 'package:flutter_test/flutter_test.dart';
import 'package:pizcloud_gallery/grid/media_item.dart';
import 'package:pizcloud_gallery/grid/sources/local_device_media_uri.dart';

void main() {
  group('LocalDeviceMediaUri typed cache key', () {
    test('separates image/video cache spaces for same source', () {
      const String source = 'pm-thumb://asset/abc?s=300';
      final String imageKey = LocalDeviceMediaUri.buildTypedThumbCacheKey(
        source,
        isVideo: false,
      );
      final String videoKey = LocalDeviceMediaUri.buildTypedThumbCacheKey(
        source,
        isVideo: true,
      );

      expect(imageKey, isNot(videoKey));
      expect(imageKey, startsWith('pm-image-cache::'));
      expect(videoKey, startsWith('pm-video-cache::'));
    });
  });

  group('MediaItem thumbnail fallback', () {
    test('fromJson builds fallback thumbnails from preview when missing', () {
      final MediaItem item = MediaItem.fromJson(<String, dynamic>{
        'id': 'm1',
        'type': 'photo',
        'sourceType': 'remote',
        'originalUrl': 'https://example.com/original.jpg',
        'previewUrl': 'https://example.com/preview.jpg',
      });

      expect(item.thumbnails.size100, 'https://example.com/preview.jpg');
      expect(item.thumbnails.size300, 'https://example.com/preview.jpg');
      expect(item.thumbnails.size600, 'https://example.com/preview.jpg');
      expect(item.pickGridThumbForEdge(300), 'https://example.com/preview.jpg');
    });

    test('video picks preview thumbnail before original', () {
      final MediaItem item = MediaItem(
        id: 'v1',
        type: MediaType.video,
        sourceType: MediaSourceType.remote,
        originalUrl: 'https://example.com/video.mp4',
        previewUrl: 'https://example.com/video-preview.jpg',
        thumbnails: const MediaThumbnails(
          size100: '',
          size300: '',
          size600: '',
        ),
      );

      expect(
        item.pickGridThumbForEdge(600),
        'https://example.com/video-preview.jpg',
      );
    });
  });
}
