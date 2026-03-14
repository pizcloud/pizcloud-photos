# Grid Scroll Playbook

## Table of Contents

1. Base Workflow
2. Wrong Visible Range or Row Mapping
3. Scrollbar Drag Mismatch
4. Fast-Scroll Stutter and Refill Lag
5. Zoom + Scroll Coupling Regressions
6. Viewer-to-Grid Sync Jumps
7. Validation Checklist
8. Guardrails

## 1. Base Workflow

1. Reproduce with a deterministic scenario:
- slow scroll.
- fast scrollbar drag.
- zoom transition plus scroll.
- viewer open then return.
2. Capture current metrics:
- call `grid.debugPrintTable()` when needed.
3. Fix one layer only (`GridState`, scrollbar widget, or gallery orchestration).
4. Re-verify all four scenarios above.

## 2. Wrong Visible Range or Row Mapping

### Use when

- Rendered rows do not match scroll position.
- Cells shift to wrong indexes near edges.

### Steps

1. Verify `GridState.getVisibleWindow(...)` inputs and extra row arguments.
2. Verify `viewportFirstCol` and `firstCellCol` updates after transform changes.
3. Verify `grid_visible_cells_builder.dart` index formula uses target column/base-cell consistently.
4. Verify `logicalRowOfDataStart` and `getDataRowCount` remain aligned after column changes.

## 3. Scrollbar Drag Mismatch

### Use when

- Thumb moves but content jumps to wrong region.
- Dragging feels unstable or noisy.

### Steps

1. Verify `_RealScrollbarMetrics.fromGrid(...)` derives:
- `currentTopRow`.
- `maxTopRow`.
- `maxThumbTravel`.
2. Verify drag path:
- `trackY -> targetThumbTop -> normalized -> targetRealTopRow`.
3. Keep frame-queued jump behavior:
- use `_queueJumpToTrackPosition`.
- avoid direct jump on every pointer event.
4. Verify `jumpToRealTopRow` mapping in `GridState` with current column settings.

## 4. Fast-Scroll Stutter and Refill Lag

### Use when

- UI stutters while dragging scrollbar.
- Cells remain low detail too long after drag release.

### Steps

1. Verify `_handleScrollbarDragStateChanged` toggles `_isScrollbarFastScrolling` correctly.
2. Verify `grid.setFastScrollActive(isDragging)` is called while initialized.
3. Verify remote prefetch is gated during drag and resumed after release.
4. Verify `TrailingThrottler` schedules `_triggerQueuePrefetch` after drag end.
5. Verify `liveWindow` uses reduced extra rows during fast drag.

## 5. Zoom + Scroll Coupling Regressions

### Use when

- After pinch/zoom, scroll jumps unexpectedly.
- Grid sticks to wrong top region.

### Steps

1. Verify scale-direction tracking lifecycle in `GridGestureController`.
2. Verify `GridState._handleTransform` clamping path does not create jump loops.
3. Keep `_isClampingScroll` checks around programmatic jumps.
4. Re-test transitions between 5/3/1 columns with current focus cell logic.

## 6. Viewer-to-Grid Sync Jumps

### Use when

- Opening/swiping viewer makes grid jump too often.

### Steps

1. Verify `ensureDataIndexVisible` hysteresis and alignment values.
2. Keep dedupe checks before invoking sync callbacks.
3. Verify sync is not running while viewer is closed.

## 7. Validation Checklist

Run:

```bash
flutter analyze lib/grid lib/viewer
flutter test test/grid
```

Manual:

1. Scroll to middle and near end using finger/mouse wheel.
2. Drag custom scrollbar quickly across long range.
3. Release drag and verify visible cells refill smoothly.
4. Zoom in/out while scrolled away from top.
5. Open viewer from scrolled position and swipe several items.
6. Close viewer and confirm grid position stays reasonable.

## 8. Guardrails

- Avoid changing row/column mapping formulas without updating related helpers together.
- Avoid removing `_isClampingScroll` protections.
- Avoid bypassing `TrailingThrottler` for frequent prefetch triggers.
- Avoid coupling scrollbar drag logic directly to heavy network/prefetch paths.
