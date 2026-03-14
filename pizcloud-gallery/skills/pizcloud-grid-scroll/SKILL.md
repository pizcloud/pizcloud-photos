---
name: pizcloud-grid-scroll
description: Maintain and debug PizGallery scroll behavior, including vertical and horizontal controllers, viewport window calculation, fast-scroll mode, and custom drag scrollbar mapping from track position to real data rows. Use when fixing wrong visible range, jumpy scrolling, scrollbar drag mismatch, scroll clamp regressions, or viewer-to-grid scroll sync issues in lib/grid/.
---

# PizCloud Grid Scroll

Use this skill to make safe changes to scroll and viewport logic in `lib/grid/*`.
Keep row-mapping math and clamping invariants stable before tuning performance behavior.

## Workflow

1. Classify the issue:
- `window mapping` (wrong rows/cols rendered for current scroll).
- `scrollbar drag` (thumb position and content position mismatch).
- `fast scroll` (lag during drag or stale prefetch after release).
- `sync` (viewer index scroll-sync jumps too often or too little).
2. Open `references/grid-scroll-map.md` to locate file ownership.
3. Use `references/grid-scroll-playbook.md` for symptom-to-fix steps.
4. Change one layer at a time (`state`, `scrollbar`, `widget orchestration`).
5. Validate manually with slow scroll, fast drag, and zoom transitions.

If the issue is primarily thumbnail resolver/cache/queue logic, use `$pizcloud-grid-runtime`.
If the issue is scanner/index/database freshness for local media, use `$pizcloud-local-source`.

## File Routing

- Scroll state and row math:
- `lib/grid/grid_state.dart`
- `lib/grid/grid_state_helper.dart`
- Scrollbar drag-to-row mapping:
- `lib/grid/real_data_scrollbar.dart`
- Gesture/scaling lock coordination:
- `lib/grid/grid_gesture_controller.dart`
- Scroll prefetch throttling and fast-scroll mode:
- `lib/grid/piz_gallery_widget.dart`
- `lib/grid/trailing_throttler.dart`
- Render window consumers:
- `lib/grid/grid_window.dart`
- `lib/grid/grid_visible_cells_builder.dart`

## Invariants To Preserve

- Keep `GridState` as the single source of truth for current scroll and row mapping.
- Keep `_isClampingScroll` guards around programmatic `jumpTo` calls to avoid feedback loops.
- Keep `jumpToRealTopRow` and `currentRealTopRow` mapping consistent with `baseRow`, `baseCells`, `firstCellCol`, and `viewportFirstCol`.
- Keep fast-scroll mode short-circuit behavior:
- `grid.setFastScrollActive(true)` during drag.
- skip heavy remote prefetch while dragging.
- resume throttled prefetch after drag ends.
- Keep `RealDataScrollbar` drag jumps queued per frame (`_queueJumpToTrackPosition`) to avoid event storms.
- Keep viewer sync behavior hysteresis-based (`ensureDataIndexVisible`), not every tick.

## Validation

1. Run:
- `flutter analyze lib/grid lib/viewer`
- `flutter test test/grid`
2. Manually verify:
- Normal slow vertical scroll has stable row mapping and no jump loops.
- Horizontal position and `viewportFirstCol` remain stable while zooming.
- Scrollbar thumb drag maps to expected content row range.
- Fast scrollbar drag enables lightweight behavior and releases cleanly.
- After drag release, prefetch resumes and visible cells refill without stale window.
- Opening viewer and swiping pages does not over-jump grid scroll.

## References

- `references/grid-scroll-map.md`
- `references/grid-scroll-playbook.md`
