# Grid Scroll Map

## Purpose

Map scroll-related responsibilities to the owning files so fixes stay localized.

## Scroll Runtime Flow

1. User scrolls with `SingleChildScrollView` controllers or drags custom scrollbar thumb.
2. `GridState` updates `scrollOffset`, computes visible window, and clamps invalid positions.
3. `PizGallery` consumes `GridWindow`, renders visible cells, and schedules prefetch.
4. During fast drag, gallery toggles fast-scroll mode and temporarily reduces heavy work.
5. On release, throttled prefetch catches up and grid returns to normal mode.

## File Ownership

- `lib/grid/grid_state.dart`
- Own vertical and horizontal controllers and transform listener.
- Own viewport calculations (`getVisibleWindow`).
- Own data-row mapping (`currentRealTopRow`, `jumpToRealTopRow`).
- Own clamping and short-content corrections (`clampScrollToFirstCell`, `_clampScrollToDataEnd`, `clampToTopWhenContentShort`).
- Own fast-scroll maintenance gate (`setFastScrollActive`).
- Own viewer-sync helpers (`isDataIndexInViewport`, `ensureDataIndexVisible`).

- `lib/grid/real_data_scrollbar.dart`
- Convert thumb drag track position to normalized row position.
- Call `grid.jumpToRealTopRow(...)` using `_RealScrollbarMetrics`.
- Queue drag updates to one frame (`_queueJumpToTrackPosition`) to reduce jitter.
- Emit drag state through `onDragStateChanged`.

- `lib/grid/piz_gallery_widget.dart`
- Wire scrollbar drag callback to `_isScrollbarFastScrolling`.
- Toggle `grid.setFastScrollActive(...)`.
- Pause heavy remote prefetch while dragging and resume after release.
- Build `liveWindow` with different extra row buffers for fast vs normal scroll.

- `lib/grid/trailing_throttler.dart`
- Debounce trailing prefetch triggers while still executing first call immediately.

- `lib/grid/grid_visible_cells_builder.dart`
- Consume `GridWindow` and materialize actual positioned cells for current scroll state.

- `lib/grid/grid_window.dart`
- Immutable visible window shape used across rendering and prefetch.

- `lib/grid/grid_gesture_controller.dart`
- Coordinate pointer count and scale-direction tracking.
- Trigger scale-end snap pipeline that can affect scroll and visible window.

## High-Risk Math Zones

- Mapping between logical rows and real data rows:
- `logicalRowOfDataStart`, `currentRealTopRow`, `jumpToRealTopRow`.
- Column offset interplay:
- `viewportFirstCol`, `firstCellCol`, `baseCells`, `baseRow`.
- Scrollbar mapping:
- `targetThumbTop -> normalized -> targetRealTopRow`.

## Change Routing

- Wrong rows rendered during scroll: start at `grid_state.dart` + `grid_visible_cells_builder.dart`.
- Scrollbar thumb drags but content jumps to wrong place: start at `real_data_scrollbar.dart` metrics + row mapping in `grid_state.dart`.
- Fast drag causes stutter or refill lag: start at `piz_gallery_widget.dart` fast-scroll gating + `TrailingThrottler`.
- Viewer open/swipe causes excessive scroll jumps: start at `ensureDataIndexVisible` in `grid_state.dart` and viewer callback usage in `piz_gallery_widget.dart`.
