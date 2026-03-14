# Viewer/Grid File Map

## Core files

- `lib/grid/piz_gallery_widget.dart`
  - Opens `ViewerPage` with `ViewerSession`.
  - Pre-warms original image cache for initial item.
  - Syncs viewer visible index back to grid with dedupe + hysteresis.
- `lib/viewer/viewer_page.dart`
  - Owns paging UI, fullscreen mode, pop/dismiss flow, and zoom gesture coordination.
  - Triggers settled side effects (prefetch + visible-index callback).
- `lib/viewer/viewer_controller.dart`
  - Stores immutable item list and current index state.
  - Owns `PageController` lifecycle.
- `lib/viewer/viewer_image_loader.dart`
  - Runs low/high quality load pipeline and cache checks.
  - Chooses fallback rendering states (loading, low quality, high quality, error).
- `lib/viewer/viewer_prefetcher.dart`
  - Builds prioritized nearby URL queue.
  - Warms disk cache and image memory cache in sequence.
- `lib/viewer/viewer_cache_manager.dart`
  - Wraps `CacheManager` + `CachedNetworkImageProvider`.
  - Defines decode width strategy and disk cache lookup policy.
- `lib/viewer/viewer_session.dart`
  - Carries startup context and callbacks across route boundary.

## Common bug triage

- **Hero flicker or wrong transition target**
  - Check hero tag generation in viewer and grid tap-open path.
- **Viewer feels janky while swiping**
  - Check that heavy side effects are attached to settled events only.
- **High-quality image never appears**
  - Check low-quality gate opening and `_allowHighQualityRequest` transitions.
- **Grid jumps too often while viewer is open**
  - Check dedupe token and hysteresis arguments in grid sync callback.
- **Cache misses despite previous opens**
  - Check decode width/height consistency between warmup and display requests.

## Safe edit strategy

1. Modify one area at a time (shell, pipeline, or integration).
2. Keep callback signatures stable unless all call sites are updated in the same patch.
3. Prefer preserving sequence points (`postFrame`, scroll-end hooks, dedupe guards).
4. Validate with `flutter analyze lib/viewer lib/grid`, then `flutter test`.
