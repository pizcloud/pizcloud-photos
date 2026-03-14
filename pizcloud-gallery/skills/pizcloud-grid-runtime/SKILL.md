---
name: pizcloud-grid-runtime
description: Maintain and extend PizGallery Flutter grid runtime, including viewport windowing, reusable grid cells, local and remote thumbnail loading, LRU byte cache behavior, and remote prefetch/download queue scheduling. Use when changing files under lib/grid/ for grid flicker, wrong thumbnail quality, local pm-thumb/pm-origin issues, cache eviction behavior, prefetch priority tuning, fast-scroll behavior, or download queue bugs.
---

# PizCloud Grid Runtime

Use this skill to make safe, performance-aware changes in `lib/grid/*` where rendering, thumbnail loading, and prefetch scheduling interact.
Keep local and remote pipelines separate, and preserve request-guarded provider swap behavior.

## Workflow

1. Classify the bug/change:
- `layout/windowing` (wrong cells/index, jumpy viewport, zoom column switch).
- `cell rendering` (blank frame, stale frame, wrong overlay, hero mismatch).
- `thumbnail loading` (local `pm-thumb`/`pm-origin` or remote HTTP/thumb URL).
- `cache/queue` (memory pressure, duplicate downloads, poor prefetch order).
2. Load map first: `references/grid-runtime-map.md`.
3. Load the specific playbook from `references/grid-runtime-playbook.md`.
4. Apply the smallest possible change in the owning layer.
5. Validate with targeted checks before broad checks.

If the root cause is scanner/index/database freshness (not cell runtime behavior),
switch to `$pizcloud-local-source`.

## File Routing

- Grid viewport/index math:
- `lib/grid/grid_state.dart`
- `lib/grid/grid_state_helper.dart`
- `lib/grid/grid_visible_cells_builder.dart`
- `lib/grid/grid_window.dart`
- Cell shell + reuse:
- `lib/grid/grid_cell.dart`
- `lib/grid/reuse_grid_cell.dart`
- `lib/grid/grid_cell_pool.dart`
- Local/remote request resolve + swap:
- `lib/grid/cell/grid_cell_resolver.dart`
- `lib/grid/cell/grid_cell_models.dart`
- Rendering and overlays:
- `lib/grid/cell/grid_cell_render.dart`
- Cache + queue + prefetch:
- `lib/grid/lru_bytes_cache.dart`
- `lib/grid/download_queue.dart`
- `lib/grid/grid_prefetch_controller.dart`
- `lib/grid/piz_gallery_widget.dart`
- URI parsing for local assets:
- `lib/grid/sources/local_device_media_uri.dart`
- Disk cache provider wrapper:
- `lib/grid/grid_thumbnail_cache_manager.dart`

## Invariants To Preserve

- Keep local and remote thumbnail prefetch paths separated:
- Remote: `GridPrefetchController` + `DownloadQueue`.
- Local: `_prefetchLocalThumbs` queue in `PizGallery`.
- Keep local image provider swap asynchronous and guarded by request token.
- Keep stale completion from overwriting active cells (`_requestToken`, `_localResolveToken`).
- Keep previous frame visible while local replacement is pending (`_lastShownLocalFrameBytes`).
- Keep video branch out of local image fallback path.
- Keep typed cache keys separated for local image vs local video (`LocalDeviceMediaUri.buildTypedThumbCacheKey`).
- Keep `GridCell` request equality tied to `mediaId + thumbUrl + decodeSide`.
- Keep queue cancellation when item exits wanted set.
- Keep fast-scroll behavior lightweight and avoid expensive remote prefetch churn while dragging scrollbar.

## Validation

1. Run:
- `flutter analyze lib/grid lib/viewer lib/media`
- `flutter test test/grid`
2. Manually verify:
- Cold open grid: no blank first paint for visible cells.
- Zoom switch (5 -> 3 -> 1 and back): no repeated flash/reload loops.
- Fast scrollbar drag: lightweight cells shown, queue recovers after release.
- Local image/video mix: no decode crash, video overlay still shown.
- Remote thumbs: priority near viewport center loads first, canceled requests do not refill stale cells.
3. If viewer integration is touched, verify viewer open from grid and back-sync still works.

## References

- `references/grid-runtime-map.md`
- `references/grid-runtime-playbook.md`
