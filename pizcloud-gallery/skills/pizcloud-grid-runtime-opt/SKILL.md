---
name: pizcloud-grid-runtime-opt
description: Optimize PizGallery runtime performance in Flutter grid flows, including render throughput, cell reuse churn, memory cache pressure, prefetch queue behavior, and fast-scroll degradation. Use when tuning FPS drops, scroll stutter, excessive RAM use, delayed thumbnail fill, queue backlogs, or costly rebuild patterns in lib/grid/.
---

# PizCloud Grid Runtime Opt

Use this skill to tune grid runtime performance with measurable before/after checks.
Focus on throughput and stability without changing data-index correctness or viewer sync behavior.

## Workflow

1. Capture baseline for the target scenario:
- `cold open`.
- `normal scroll`.
- `fast scrollbar drag`.
- `zoom transitions (5/3/1 cols)`.
2. Identify bottleneck class:
- `rebuild/churn`.
- `decode/cache`.
- `queue/prefetch`.
- `scrollbar/fast-scroll`.
3. Open `references/grid-runtime-opt-hotspots.md` and choose the owning knob set.
4. Apply one tuning change at a time.
5. Re-measure and keep only changes that improve target metrics without regressions.

If the issue is a functional bug (wrong index, wrong media, wrong mapping), use `$pizcloud-grid-runtime` or `$pizcloud-grid-scroll` first.
Use this skill after correctness is stable.

## Core Metrics

- `FPS`: use `FpsMonitor`/`FpsBadge` during scroll scenarios.
- `fill latency`: time until visible cells show expected thumbnails after scroll/drag.
- `queue pressure`: pending/inflight growth behavior while moving viewport.
- `memory`: `LruBytesCache.totalBytes`, bucket distribution, eviction churn.
- `rebuild pressure`: visible cell rebuild count and reuse hit ratio.

## Tuning Areas

- Reuse and render workload:
- `lib/grid/grid_visible_cells_builder.dart`
- `lib/grid/grid_cell_pool.dart`
- `lib/grid/reuse_grid_cell.dart`
- Memory cache:
- `lib/grid/lru_bytes_cache.dart`
- `lib/grid/piz_gallery_widget.dart` (`_memoryCacheMaxMb`, `_memoryCacheSize50MaxMb`)
- Prefetch and queue:
- `lib/grid/grid_prefetch_controller.dart`
- `lib/grid/download_queue.dart`
- `lib/grid/piz_gallery_widget.dart` (`_prefetchRowsAhead`, `_prefetchRowsBehind`, `_prefetchThrottleMs`, `_maxDownloadConcurrent`)
- Fast-scroll degradation strategy:
- `lib/grid/piz_gallery_widget.dart` (`lightweightMode`, `_fastScrollThumbEdge`, drag state gating)
- Scrollbar drag event load:
- `lib/grid/real_data_scrollbar.dart` (frame-queued jump behavior)

## Invariants To Preserve

- Do not break data-index mapping correctness for cells.
- Do not mix local and remote prefetch queues.
- Keep fast-scroll fallback reversible: restore normal quality/prefetch after drag ends.
- Keep viewer sync behavior (`ensureDataIndexVisible`) hysteresis-based.
- Keep local video safety path (never decode local video as image).
- Keep request-token guards in cell resolver intact when tuning asynchronous behavior.

## Validation

1. Run:
- `flutter analyze lib/grid lib/viewer`
- `flutter test test/grid`
2. Manual performance pass:
- compare FPS in same scripted gesture sequence.
- compare first-fill delay after fast drag release.
- compare cache memory footprint and eviction behavior.
- compare queue backlog recovery time after viewport changes.
3. Abort tuning if a functional regression appears, then revert and re-scope.

## References

- `references/grid-runtime-opt-hotspots.md`
- `references/grid-runtime-opt-playbook.md`
