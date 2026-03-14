---
name: pizcloud-viewer-grid
description: Maintain and extend the PizCloud Flutter viewer and grid integration, including Hero transitions, zoom/dismiss gestures, image loading quality gates, cache/prefetch behavior, and viewer-to-grid index sync. Use when changing files under lib/viewer/ or the viewer bridge in lib/grid/piz_gallery_widget.dart, or when debugging viewer performance and state coordination bugs.
---

# PizCloud Viewer Grid

## Overview

Use this skill to make safe, performance-aware changes in the gallery viewer stack and its integration with the grid.

## Workflow

1. Classify the requested change before editing.
2. Read `local/docs/viewer/viewer_call_graph.md` for current flow and side effects.
3. Open only the files in the relevant area from `references/viewer-grid-map.md`.
4. Preserve the invariants listed below while implementing.
5. Run focused validation commands before broad checks.

## Change Areas

- **Viewer shell and paging**: Edit `lib/viewer/viewer_page.dart` and `lib/viewer/viewer_controller.dart`.
- **Image pipeline**: Edit `lib/viewer/viewer_image_loader.dart`, `lib/viewer/viewer_cache_manager.dart`, and `lib/viewer/viewer_prefetcher.dart`.
- **Grid integration**: Edit `lib/grid/piz_gallery_widget.dart` and `lib/viewer/viewer_session.dart`.
- **UI style only**: Edit `lib/viewer/viewer_appearance_config.dart` unless behavior also changes.

## Invariants

- Keep heavy side effects (prefetch + grid sync) on settled page motion, not per drag tick.
- Keep `ViewerSession.clampedInitialIndex` as the single clamp source for startup index.
- Keep Hero tags stable via media id (`mediaViewerHeroTag` / grid hero helpers).
- Keep low-quality gate behavior: request high-quality after low-quality gate opens unless original is already cached.
- Keep decode width bounded by context and original image dimensions.
- Keep viewer-to-grid sync deduplicated and hysteresis-aware (`ensureDataIndexVisible`).

## Validation

1. Run `flutter analyze lib/viewer lib/grid`.
2. Run `flutter test`.
3. Manually verify:
   - Open from grid to viewer with Hero transition.
   - Swipe between pages and confirm grid sync remains stable.
   - Pinch/drag dismiss behavior does not lock navigation unexpectedly.
   - Cached images render quickly when reopening viewer.

## References

- Use `references/viewer-grid-map.md` for file responsibilities and debugging shortcuts.
- Use `local/docs/viewer/viewer_call_graph.md` for end-to-end flow diagrams.
