# Grid Runtime Map

## Purpose

Map each grid-runtime responsibility to concrete files and runtime flow so fixes stay localized.

## End-to-End Runtime Flow

1. `PizGallery` computes visible `GridWindow` from scroll/transform state.
2. `GridVisibleCellsBuilder` maps window row/col to `dataIndex`, builds `CellData`, and chooses thumb URL edge.
3. `GridCell` receives `CellData` and runs resolver logic:
- remote path -> cache check -> provider build -> async resolve and swap.
- local path -> URI parse (`pm-thumb`/`pm-origin`) -> local thumb/file resolve -> async swap.
4. `GridCell` render layer displays provider or held/fallback frame with media overlays.
5. Prefetch runs in parallel:
- remote: `GridPrefetchController` -> `DownloadQueue` -> `LruBytesCache`.
- local: `_prefetchLocalThumbs` queue in `PizGallery` -> `LruBytesCache`.

## File Ownership

- `lib/grid/piz_gallery_widget.dart`
- Own lifecycle (`_bootstrap`, runtime init/dispose), fast-scroll mode, and prefetch scheduling.
- Run remote prefetch via `_prefetchController.update(window)`.
- Run local prefetch via `_prefetchLocalThumbs(window)` with epoch/cancel guards.

- `lib/grid/grid_state.dart`
- Own transform/scroll state, viewport window computation, row/col and data-index visibility logic.
- Expose `getVisibleWindow`, `ensureDataIndexVisible`, and scale-column transitions.

- `lib/grid/grid_visible_cells_builder.dart`
- Build visible positioned cells and reuse-cell pipeline.
- Resolve `thumbEdge` and `thumbUrl` for each `CellData`.
- Convert local media thumb targets to `pm-thumb://...` when possible.

- `lib/grid/grid_cell.dart`
- Own state fields and shared caches for shown providers and in-flight local futures.
- Wire hero wrapper, tap behavior, and render/resolver split parts.

- `lib/grid/cell/grid_cell_resolver.dart`
- Build request identity (`mediaId`, `thumbUrl`, `decodeSide`).
- Handle remote/local branching and provider swap only after resolve.
- Guard stale async with `_requestToken` and `_localResolveToken`.
- Handle local thumb failures and image-file fallback behavior.

- `lib/grid/cell/grid_cell_render.dart`
- Render main image, local held-frame fallback, and video overlays.
- Use gapless rendering and stable thumb keys for smoother swaps.

- `lib/grid/lru_bytes_cache.dart`
- Store in-memory bytes with LRU behavior and key-level notifiers.
- Keep separate bucket logic for local `pm-thumb` edge-50 keys.

- `lib/grid/download_queue.dart`
- Manage remote pending/inflight queues with priority/fifo/lifo strategies.
- Cancel in-flight downloads when URL leaves wanted set.

- `lib/grid/grid_prefetch_controller.dart`
- Convert current window into wanted remote URL set and distance-based priorities.
- Feed queue by calling `setWanted` and `ensureMany`.

- `lib/grid/grid_thumbnail_cache_manager.dart`
- Build file/network `ImageProvider` and optional disk-cache path for remote images.

- `lib/grid/sources/local_device_media_uri.dart`
- Build/parse local URI schemes and typed cache keys (`pm-image-cache`, `pm-video-cache`).

## Key Data Structures

- `CellData`: visual payload for each rendered cell.
- `_ThumbRequest`: request identity for swap dedupe and stale guard.
- `_LocalSourceRequest`: parsed local source kind (`assetThumb`, `assetFile`, `filePath`, `unsupported`).
- `_LocalThumbPrefetchRequest`: background local prefetch payload.
- `DownloadQueueItem`: URL + numeric priority for remote queue.

## High-Risk Edit Zones

- `grid_state.dart` window/index math:
- Risk: wrong data-index mapping and jumpy scroll behavior.
- `grid_cell_resolver.dart` token/cancel logic:
- Risk: stale async completion overwriting the wrong cell.
- `lru_bytes_cache.dart` eviction logic:
- Risk: hot keys churn and repeated decode/network work.
- `download_queue.dart` wanted/inflight/pending transitions:
- Risk: wasted downloads and starvation near viewport center.
