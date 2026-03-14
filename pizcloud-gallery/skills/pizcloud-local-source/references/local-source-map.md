# Local Source Map

## Purpose

Map each local-source responsibility to the owning file so fixes stay focused.

## Data Flow

1. Device media query (`photo_manager`)
2. Scan + transform local assets into media records
3. Upsert/reconcile records in local DB
4. Build `PizGallerySource` snapshot/updates from DB
5. Expose local URI contracts consumed by grid/viewer

## File Ownership

- `lib/media/local_media_scanner.dart`
  - PhotoManager scan strategy
  - Incremental/full scan policy
  - Scan progress payload
  - Checkpoint/meta updates

- `lib/media/media_repository.dart`
  - Upsert local/remote rows
  - Fetch local rows for source
  - Reconcile missing local assets
  - Get/set scan metadata

- `lib/media/media_db.dart`
  - Schema version and migration
  - Indexes for local/read paths
  - Meta table definition

- `lib/grid/sources/local_indexed_gallery_source.dart`
  - Load initial snapshot from DB
  - Trigger background scan
  - Emit debounced updates
  - Limit-growth strategy during scan

- `lib/grid/sources/local_device_media_uri.dart`
  - Build/parse local URI schemes (`pm-thumb`, `pm-origin`)

- `lib/viewer/viewer_image_loader.dart`
  - Resolve local original URI to asset file
  - Render local full image in viewer

- `local/skills/pizcloud-grid-runtime/*`
  - Own grid cell resolver/render/cache/queue runtime behavior.
  - Use this when debugging visual flicker, local thumb swap, or prefetch order.

## Change Routing

- Slow initial local load -> source/db layer first.
- Missing/deleted local items -> scanner + repository reconcile.
- Thumbnail decode errors or grid flicker -> hand off to `pizcloud-grid-runtime`.
- Viewer cannot load local original -> viewer loader URI handling.
- List jumping/reordering -> source emit + sort fields.
