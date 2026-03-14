# pizcloud_gallery

`PizGallery` is now source-driven: host apps inject data through `PizGallerySource`.

## Public APIs

- Core gallery API:
  - `import 'package:pizcloud_gallery/grid/piz_gallery.dart';`
- Testing/sample helpers:
  - `import 'package:pizcloud_gallery/grid/piz_gallery_testing.dart';`

## Quick Start

```dart
final source = JsonAssetGallerySource(
  assetPath: 'assets/mock/picsum_media_sample.json',
);

PizGallery(
  source: source,
  enableReuseCell: true,
);
```

## Source Types

- `PizGallerySource`: contract for initial snapshot + optional live updates.
- `InMemoryGallerySource`: mutable test/demo source (`replaceAll`, `append`).
- `JsonAssetGallerySource`: load snapshot from JSON asset.
- `LocalDeviceGallerySource`: load real local files from device gallery.
- `LocalDatabaseGallerySource`: read local items from indexed DB (read-only).
- `IndexedLocalGallerySource` (deprecated): old name of `LocalDatabaseGallerySource`.
- `LocalMediaScanService`: scan local device and upsert into indexed DB.
- `LocalGalleryScanProcess`: run scan on a separate process/timer and push refresh to read-only source.
- `AutoScanLocalIndexedSource` / `LocalIndexedGallerySource`: compose read + background scan.
- `RemoteGallerySource` / `LocalGallerySource`: callback adapters for existing app data layers.
- `HybridGallerySource`: merge local + remote into one feed, with dedupe and priority.

## Local DB Only + Separate Scan

```dart
final localSource = LocalDatabaseGallerySource(
  initialLoadCount: 120,
  // maxItems is optional. null means no limit.
);

final scanProcess = LocalGalleryScanProcess(
  source: localSource,
  periodicInterval: const Duration(minutes: 15),
  startImmediately: true,
);

await scanProcess.start();
```

## Extending with Real Data

1. Keep your existing repository/service layer unchanged.
2. Map records into `MediaItem`.
3. Wrap loaders with `LocalGallerySource` or `RemoteGallerySource`.
4. If needed, combine both via `HybridGallerySource`.
5. Pass the final source into `PizGallery`.
