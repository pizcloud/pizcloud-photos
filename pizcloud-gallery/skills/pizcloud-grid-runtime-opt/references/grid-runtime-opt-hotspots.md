# Grid Runtime Optimization Hotspots

## Purpose

Map performance hotspots to concrete tuning knobs in the grid runtime.

## Hotspot 1: Rebuild and Cell Churn

### Symptoms

- FPS drops during moderate scroll.
- Many cells rebuild even when visual payload is unchanged.

### Knobs and Files

- `lib/grid/grid_visible_cells_builder.dart`
- `enableReuseCell` path versus non-reuse path.
- `lightweightMode` path during fast drag.
- `CellData.sameVisual(...)` sensitivity affects notifier update frequency.

- `lib/grid/grid_cell_pool.dart`
- Active/pool reuse behavior and release cadence.

- `lib/grid/reuse_grid_cell.dart`
- Rebuild path through `ValueListenableBuilder<CellData>`.

### Guardrails

- Preserve correct keying (`logicalIndex`) so reused cells do not show wrong media.

## Hotspot 2: Thumbnail Decode and Memory Pressure

### Symptoms

- Frequent stutter spikes after scrolling into new regions.
- Repeated decode work and cache churn.

### Knobs and Files

- `lib/grid/piz_gallery_widget.dart`
- `_memoryCacheMaxMb`.
- `_memoryCacheSize50MaxMb`.
- `_fastScrollThumbEdge` (quality/decode tradeoff while dragging).

- `lib/grid/lru_bytes_cache.dart`
- Bucket split (`default` vs `size50`).
- Eviction behavior and key signal churn.

- `lib/grid/cell/grid_cell_resolver.dart`
- Swap behavior with cache hits versus async resolve.

### Guardrails

- Keep typed local keys separated by media type.
- Avoid reducing memory budgets so far that visible-region re-decode explodes.

## Hotspot 3: Prefetch Throughput and Queue Backlog

### Symptoms

- Visible cells stay empty too long after scroll.
- Queue grows faster than completion.

### Knobs and Files

- `lib/grid/piz_gallery_widget.dart`
- `_prefetchRowsAhead`, `_prefetchRowsBehind`.
- `_prefetchThrottleMs`.
- `_maxDownloadConcurrent`.
- `_enableCompactPending`, `_compactFactor`.

- `lib/grid/grid_prefetch_controller.dart`
- Window expansion range and priority assignment.

- `lib/grid/download_queue.dart`
- Strategy (`priority2d`/`fifo`/`lifo`) and cancellation flow.
- Wanted-set compaction and duplicate suppression.

### Guardrails

- Keep cancellation for off-viewport inflight items.
- Keep center-priority behavior if UX depends on nearest-first fill.

## Hotspot 4: Fast Scroll Degradation and Recovery

### Symptoms

- Drag is janky or laggy.
- Recovery after release is slow or incomplete.

### Knobs and Files

- `lib/grid/piz_gallery_widget.dart`
- `_isScrollbarFastScrolling` gating.
- Fast-drag `lightweightMode` + low-edge overlay path.
- Resume path via `_prefetchThrottler.schedule(_triggerQueuePrefetch)`.

- `lib/grid/real_data_scrollbar.dart`
- Frame-queued drag updates (`_queueJumpToTrackPosition`) to reduce jump flood.

- `lib/grid/trailing_throttler.dart`
- Interval size versus responsiveness tradeoff.

### Guardrails

- Do not leave app stuck in fast-scroll mode after drag end.
- Ensure normal render quality returns after release.

## Hotspot 5: Scroll/Zoom Coupling Cost

### Symptoms

- Zoom transitions trigger expensive scroll corrections repeatedly.

### Knobs and Files

- `lib/grid/grid_state.dart`
- Transform listener and clamp paths.
- Short-content and bounds clamp logic.
- Scale-direction driven column target transitions.

- `lib/grid/grid_state_helper.dart`
- Scale decision thresholds and hysteresis ratios.

### Guardrails

- Preserve index/row correctness while tuning clamp frequency.
