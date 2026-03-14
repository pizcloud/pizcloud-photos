# Grid Runtime Playbook

## Table of Contents

1. Workflow for Any Grid Runtime Change
2. Playbook: Grid Window and Cell Index Issues
3. Playbook: Local Thumbnail Load/Flicker Issues
4. Playbook: Remote Thumbnail/Queue Issues
5. Playbook: Cache Tuning and Memory Pressure
6. Validation Checklist
7. Guardrails

## 1. Workflow for Any Grid Runtime Change

1. Reproduce with explicit scenario:
- local images, local videos, remote images, or mixed list.
- normal scroll, fast scrollbar drag, or zoom column transition.
2. Map symptom to owner:
- index/window problem -> `grid_state.dart` / `grid_visible_cells_builder.dart`.
- image swap/flicker -> `grid_cell_resolver.dart` / `grid_cell_render.dart`.
- cache/queue behavior -> `lru_bytes_cache.dart` / `download_queue.dart`.
3. Change only one layer first.
4. Re-run targeted checks.
5. Expand validation to mixed-media and fast-scroll scenarios.

## 2. Playbook: Grid Window and Cell Index Issues

### Use when

- Wrong media appears in a cell.
- Viewer opens wrong item from tapped cell.
- Layout jumps or leaves empty columns during zoom transitions.

### Steps

1. Verify window math in `GridState.getVisibleWindow`.
2. Verify index mapping in `GridVisibleCellsBuilder._buildCellData`:
- `logicalRow * targetColCount + col - baseCells[targetColCount]`.
3. Verify column clipping behavior in `_resolveRenderCols` (settled scale vs scaling).
4. Verify local thumb URL override logic in `_resolveThumbUrlForEdge`.
5. Verify `CellData.sameVisual` fields if cells do not refresh/reuse correctly.

### Quick checks

- Drag vertically and horizontally near boundaries.
- Zoom in/out repeatedly (`5 -> 3 -> 1 -> 3 -> 5`) and inspect index continuity.

## 3. Playbook: Local Thumbnail Load/Flicker Issues

### Use when

- Local cells flash blank while scrolling or zooming.
- Local image thumbs fail repeatedly.
- Local videos accidentally go through image decode path.

### Steps

1. Verify local source request parse in `_buildLocalSourceRequest`:
- `pm-thumb://` -> `assetThumb`.
- `pm-origin://` -> `assetFile`.
- `/path` or `file://` -> `filePath`.
2. Keep asynchronous swap behavior:
- call `_resolveAndSwap` only after provider resolve callback.
- avoid direct provider replacement without stale guard.
3. Keep stale request guards:
- `_localResolveToken` for local resolve chain.
- `_requestToken` for image stream resolve callbacks.
4. Keep held-frame fallback in render layer:
- `_rememberLocalCellFrame` and `_buildHeldLocalFrameImage`.
5. Keep local failure cache behavior:
- `_markFailedLocalThumbKey` and `_isFailedLocalThumbKey`.
- fallback to asset file only for local image branch, not video branch.
6. Keep typed cache keys:
- use `LocalDeviceMediaUri.buildTypedThumbCacheKey` so image/video caches do not collide.

### Typical fixes

- Do not reintroduce `FutureBuilder` placeholder-driven swapping for local thumbs.
- Do not route local videos to `Image.file` fallback.
- Cache resolved local thumb bytes before swapping provider.

## 4. Playbook: Remote Thumbnail/Queue Issues

### Use when

- Remote thumbs load out of order or too late.
- Queue grows excessively and downloads become stale.
- Off-viewport downloads continue too long.

### Steps

1. Verify URL resolver in `_resolvePrefetchUrlAt`:
- skip local items.
- use adaptive edge choice via `pickGridThumbAdaptive`.
2. Verify prefetch window expansion in `GridPrefetchController.update`.
3. Verify queue wanted-set updates:
- `setWanted` should cancel inflight URLs no longer wanted.
4. Verify priority behavior:
- `priority = abs(row-centerRow) + abs(col-centerCol)`.
- lower number means higher priority.
5. Verify duplicate suppression in queue:
- skip if already cached/inflight/queued.
6. Verify compaction behavior (`enableCompact`, `compactFactor`) if pending grows too much.

### Fast-scroll handling

- Keep remote prefetch throttled/paused while scrollbar drag is active.
- Resume queued prefetch after drag ends.
- Keep lightweight rendering active during drag to reduce load.

## 5. Playbook: Cache Tuning and Memory Pressure

### Use when

- Memory spikes after long scroll sessions.
- Frequent cache misses cause repeated decode/network work.
- Local edge-50 thumbs evict more useful entries.

### Steps

1. Inspect `LruBytesCache` budgets:
- default bucket: `maxBytes`.
- edge-50 local bucket: `size50MaxBytes`.
2. Verify key classification:
- `_isSize50ThumbKey` should only match `pm-thumb` with `s=50`.
3. Verify eviction side effects:
- `_bumpSignal(removedKey)` should trigger key listeners to refresh.
4. Tune budgets in `PizGallery` constants:
- `_memoryCacheMaxMb`.
- `_memoryCacheSize50MaxMb`.
5. Re-check queue concurrency:
- `_maxDownloadConcurrent` too high can inflate temporary memory use.

## 6. Validation Checklist

Run:

```bash
flutter analyze lib/grid lib/viewer lib/media
flutter test test/grid
```

Manual:

1. Cold launch with mixed local/remote media and scroll immediately.
2. Perform fast scrollbar drag, then release and confirm visible cells recover fast.
3. Zoom transitions across column modes and watch for blank frames.
4. Open viewer from grid and confirm return sync keeps target index in viewport.
5. Trigger local thumb failures (if available) and verify no infinite retry loops.

## 7. Guardrails

- Avoid mixing local and remote prefetch queues.
- Avoid bypassing request-token guards when touching async resolver code.
- Avoid replacing provider immediately before image stream resolves.
- Avoid changing `CellData.sameVisual` fields without retesting reuse behavior.
- Avoid broad queue/cache tuning without manual fast-scroll verification.
