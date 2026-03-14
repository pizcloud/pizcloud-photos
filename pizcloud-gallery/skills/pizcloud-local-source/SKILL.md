---
name: pizcloud-local-source
description: Optimize and debug PizGallery local media source on Flutter/Android/iOS with PhotoManager-backed scanning, local indexing, and thumbnail rendering fallback. Use when implementing local gallery loading, fixing slow local load, handling Glide/thumbnail decode errors, adding incremental/full scan logic, reconciling deleted local assets in DB, or tuning grid/viewer behavior for local media.
---

# Pizcloud Local Source

## Overview

Use this skill to implement or maintain a stable local-media pipeline:
PhotoManager scan -> indexed storage -> source updates -> grid/viewer rendering.
Keep local loading fast, avoid repeated decode failures, and preserve predictable UX.

## Workflow

1. Confirm scope and current behavior.
2. Map the issue to the right layer (`scanner`, `repository/db`, `source`, `viewer`).
3. Apply the minimal change at that layer.
4. Validate with analyze/tests and targeted manual checks on device.

Use `references/local-source-map.md` to pick files quickly.
Use `references/local-source-troubleshooting.md` for symptom-to-fix mapping.
When the issue is primarily grid runtime behavior (cell swap/flicker/cache/queue),
switch to `$pizcloud-grid-runtime` and keep this skill focused on local source logic.

## Implement Local Scan and Index

- Keep scan logic in `lib/media/local_media_scanner.dart`.
- Prefer incremental scan by `modifiedAt` checkpoint for normal runs.
- Run periodic full scan and reconcile stale local rows.
- Store scan metadata (last full scan, max modified timestamp) in a meta table.
- Keep DB migration and index changes in `lib/media/media_db.dart`.
- Keep query/upsert/reconcile operations in `lib/media/media_repository.dart`.

## Implement Source Update Strategy

- Keep source adaptation in `lib/grid/sources/local_indexed_gallery_source.dart`.
- Load a small initial snapshot fast, then scan in background.
- Emit updates with debounce.
- Increase emit limit progressively during scan to reduce churn and large re-queries.
- Keep sort/filter stable by ID + timestamp fields to avoid list jumping.

## Coordinate Local Thumbnail Boundaries

- Keep local URI contract in `lib/grid/sources/local_device_media_uri.dart`:
  - `pm-thumb://` for thumbnail lookup.
  - `pm-origin://` for original file lookup.
- Keep source outputs stable so grid/viewer consumers receive predictable local URLs.
- Keep local media metadata complete (`type`, `width`, `height`, timestamps) to avoid downstream render ambiguity.
- Keep viewer local-original behavior in `lib/viewer/viewer_image_loader.dart`.
- For grid cell swap/render/cache queue internals, use `$pizcloud-grid-runtime` to avoid duplicated maintenance.

## Validation Checklist

- Run:
  - `flutter analyze lib/media lib/grid lib/features/library lib/viewer`
  - `flutter test`
- Manually verify:
  - First load uses indexed data quickly.
  - Background scan fills more items without blocking UI.
  - Problematic local assets do not crash or spam errors repeatedly.
  - Grid receives valid local thumb/original URIs from source rows.
  - Grid shows local video tile placeholder, not decode crash.
  - Viewer opens local image from asset/original URI.

## Guardrails

- Do not block initial UI on full local scan.
- Do not run heavy file-size reads for all assets unless explicitly required.
- Do not treat every Glide warning as fatal; suppress repeated retries by caching failures.
- Do not reintroduce image decode path for local videos.
- Do not add non-essential docs/files to this skill.
