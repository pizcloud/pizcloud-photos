# Local Source Troubleshooting

## Symptom -> Action

### 1) Grid local thumbnails load very slowly

- Verify source is `LocalIndexedGallerySource`, not direct full scan source.
- Verify initial load count is limited (for example 80-150).
- Verify scanner runs in background and emits incremental updates.
- Verify DB has local indexes for created/modified ordering.

### 2) Repeated Glide warnings (`setDataSource failed: status = 0x80000000`)

- Treat as per-asset decode failure, not app-wide fatal.
- Confirm local URI records are valid (`pm-thumb` / `pm-origin`) and asset IDs are not stale.
- If issue is in grid cell fallback/swap logic, hand off to `$pizcloud-grid-runtime`.

### 3) `Failed to decode image` / FlutterJNI decode exception

- Confirm source classification (`photo` vs `video`) is correct in indexed rows.
- If render-path decode is wrong (`Image.file`/`Image.memory` for video), hand off to `$pizcloud-grid-runtime`.

### 4) Local list stale after user deletes photos

- Run periodic full scan.
- After full scan, reconcile rows that were not touched in this scan:
  - If row also has `remote_id`: convert to `cloudOnly`.
  - If local-only row: delete row.
- Persist scan marker and update timestamps consistently.

### 5) Local updates cause UI jumps

- Use deterministic sort keys (`COALESCE(created_at, modified_at)` + stable ID).
- Debounce updates from scanner progress.
- Increase emitted limit progressively instead of always fetching max list.

### 6) First zoom column-change flashes background (local only)

- This is a grid runtime concern, not source/index concern.
- Use `$pizcloud-grid-runtime` and follow `references/grid-runtime-playbook.md` section 3.

### 7) Video tile behavior differs between remote and local

- This is a grid cell resolver/render concern.
- Use `$pizcloud-grid-runtime` and keep this skill focused on source/index fidelity.

## Quick Verification Script

Run after each meaningful local-source change:

```bash
flutter analyze lib/media lib/grid lib/features/library lib/viewer
flutter test
```

Then verify manually on a real device:

1. Open gallery from cold start.
2. Confirm initial content appears quickly.
3. Scroll while background updates arrive.
4. Open problematic local assets (including videos).
5. Check logs: failures should not loop endlessly.
