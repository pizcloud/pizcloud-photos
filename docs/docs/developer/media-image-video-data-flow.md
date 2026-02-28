---
title: Luồng Dữ Liệu và Field Ảnh Video
---

# Luồng Dữ Liệu và Field Ảnh/Video

Tài liệu này tổng hợp:

- Toàn bộ field liên quan tới lưu trữ ảnh/video trong hệ thống (server và mobile).
- Vị trí source code lưu các field đó (schema/entity/repository/service).
- Luồng đọc/ghi dữ liệu để dễ quản lý, mở rộng và debug.

## 1. Tổng Quan Kiến Trúc Dữ Liệu

Hiện tại hệ thống đang có 3 lớp dữ liệu chính:

1. `Server (PostgreSQL)`: nguồn sự thật (source of truth) cho asset remote.
2. `Mobile Drift (SQLite)`: lớp local mới để lưu remote/local và phục vụ timeline.
3. `Mobile Isar`: lớp dữ liệu cũ (legacy), vẫn còn được dùng ở một số luồng.

Điểm khởi tạo đồng thời Drift + Isar:

- `mobile/lib/utils/bootstrap.dart`

Điểm đăng ký các bảng Drift:

- `mobile/lib/infrastructure/repositories/db.repository.dart`

## 2. Data Dictionary: Mobile Drift (SQLite)

### 2.1 Field dùng chung cho asset (mixin)

File:

- `mobile/lib/infrastructure/utils/asset.mixin.dart`

Các field:

- `name`
- `type`
- `createdAt`
- `updatedAt`
- `width`
- `height`
- `durationInSeconds`

### 2.2 Bảng local asset

File:

- `mobile/lib/infrastructure/entities/local_asset.entity.dart`

Bảng: `local_asset_entity`

Các field:

- `id` (PK)
- `checksum` (nullable)
- `isFavorite`
- `orientation`
- Cộng thêm toàn bộ field từ `AssetEntityMixin`

Index quan trọng:

- `idx_local_asset_checksum`

### 2.3 Bảng remote asset

File:

- `mobile/lib/infrastructure/entities/remote_asset.entity.dart`

Bảng: `remote_asset_entity`

Các field:

- `id` (PK)
- `checksum`
- `isFavorite`
- `ownerId`
- `localDateTime`
- `thumbHash`
- `deletedAt`
- `livePhotoVideoId`
- `visibility`
- `stackId`
- `libraryId`
- Cộng thêm toàn bộ field từ `AssetEntityMixin`

Index/constraint quan trọng:

- `idx_remote_asset_owner_checksum`
- `UQ_remote_assets_owner_checksum` (khi `library_id IS NULL`)
- `UQ_remote_assets_owner_library_checksum` (khi `library_id IS NOT NULL`)
- `idx_remote_asset_checksum`

### 2.4 Bảng local asset đã đưa vào thùng rác

File:

- `mobile/lib/infrastructure/entities/trashed_local_asset.entity.dart`

Bảng: `trashed_local_asset_entity`

Các field:

- `id`
- `albumId`
- `checksum`
- `isFavorite`
- `orientation`
- Cộng thêm toàn bộ field từ `AssetEntityMixin`

Primary key:

- `(id, albumId)`

Index:

- `idx_trashed_local_asset_checksum`
- `idx_trashed_local_asset_album`

### 2.5 Bảng EXIF remote

File:

- `mobile/lib/infrastructure/entities/exif.entity.dart` (`RemoteExifEntity`)

Bảng: `remote_exif_entity`

Các field:

- `assetId` (PK/FK tới remote asset)
- `city`
- `state`
- `country`
- `dateTimeOriginal`
- `description`
- `height`
- `width`
- `exposureTime`
- `fNumber`
- `fileSize`
- `focalLength`
- `latitude`
- `longitude`
- `iso`
- `make`
- `model`
- `lens`
- `orientation`
- `timeZone`
- `rating`
- `projectionType`

Index:

- `idx_lat_lng` trên `(latitude, longitude)`

### 2.6 Các bảng relation liên quan ảnh/video

File:

- `mobile/lib/infrastructure/entities/local_album_asset.entity.dart`
- `mobile/lib/infrastructure/entities/remote_album_asset.entity.dart`
- `mobile/lib/infrastructure/entities/stack.entity.dart`
- `mobile/lib/infrastructure/entities/asset_face.entity.dart`

Field chính:

- `local_album_asset_entity`: `assetId`, `albumId`, `marker_`
- `remote_album_asset_entity`: `assetId`, `albumId`
- `stack_entity`: `id`, `createdAt`, `updatedAt`, `ownerId`, `primaryAssetId`
- `asset_face_entity`: `id`, `assetId`, `personId`, `imageWidth`, `imageHeight`, `boundingBoxX1`, `boundingBoxY1`, `boundingBoxX2`, `boundingBoxY2`, `sourceType`

### 2.7 Query hợp nhất remote + local cho timeline

File:

- `mobile/lib/infrastructure/entities/merged_asset.drift`

Query:

- `mergedAsset`
- `mergedBucket`

Ý nghĩa:

- Lấy remote asset (visible timeline, chưa xóa, đúng stack primary) + local asset chưa có remote match theo `checksum`.
- Dùng cho Home timeline để tránh trùng local/remote.

## 3. Data Dictionary: Mobile Isar (Legacy, vẫn còn dùng)

### 3.1 Collection Asset

File:

- `mobile/lib/entities/asset.entity.dart`

Collection: `Asset`

Field được persist:

- `id`
- `checksum`
- `thumbhash`
- `remoteId`
- `localId`
- `ownerId`
- `fileCreatedAt`
- `fileModifiedAt`
- `updatedAt`
- `durationInSeconds`
- `type`
- `width`
- `height`
- `fileName`
- `livePhotoVideoId`
- `isFavorite`
- `isArchived`
- `isTrashed`
- `isOffline`
- `stackId`
- `stackPrimaryAssetId`
- `stackCount`
- `visibility`

Lưu ý:

- `exifInfo` trong class `Asset` là `@ignore`, không nằm trong cùng collection.

### 3.2 Collection Exif (Isar)

File:

- `mobile/lib/infrastructure/entities/exif.entity.dart` (`ExifInfo` có `@Collection`)

Field:

- `id`
- `fileSize`
- `dateTimeOriginal`
- `timeZone`
- `make`
- `model`
- `lens`
- `f`
- `mm`
- `iso`
- `exposureSeconds`
- `lat`
- `long`
- `city`
- `state`
- `country`
- `description`
- `orientation`

## 4. Data Dictionary: Server PostgreSQL

### 4.1 Nơi đăng ký schema tổng

File:

- `server/src/schema/index.ts`

Các bảng media/chính:

- `asset`
- `asset_exif`
- `asset_file`
- `asset_metadata`
- `asset_face`
- `stack`
- `album_asset`
- `memory_asset`
- `asset_job_status`
- `asset_ocr`

### 4.2 Bảng asset (cốt lõi)

File:

- `server/src/schema/tables/asset.table.ts`

Các field:

- `id`
- `deviceAssetId`
- `ownerId`
- `deviceId`
- `type`
- `originalPath`
- `fileCreatedAt`
- `fileModifiedAt`
- `isFavorite`
- `duration`
- `encodedVideoPath`
- `checksum`
- `livePhotoVideoId`
- `updatedAt`
- `createdAt`
- `originalFileName`
- `sidecarPath`
- `thumbhash`
- `isOffline`
- `libraryId`
- `isExternal`
- `deletedAt`
- `localDateTime`
- `stackId`
- `duplicateId`
- `status`
- `updateId`
- `visibility`

Constraint/index quan trọng:

- Unique checksum theo `(ownerId, checksum)` khi `libraryId is null`.
- Unique checksum theo `(ownerId, libraryId, checksum)` khi `libraryId is not null`.
- Index theo `localDateTime`, `originalPath + libraryId`, `id + stackId`, và trigram `originalFileName`.

### 4.3 Bảng asset_exif

File:

- `server/src/schema/tables/asset-exif.table.ts`

Các field:

- `assetId`
- `make`
- `model`
- `exifImageWidth`
- `exifImageHeight`
- `fileSizeInByte`
- `orientation`
- `dateTimeOriginal`
- `modifyDate`
- `lensModel`
- `fNumber`
- `focalLength`
- `iso`
- `latitude`
- `longitude`
- `city`
- `state`
- `country`
- `description`
- `fps`
- `exposureTime`
- `livePhotoCID`
- `timeZone`
- `projectionType`
- `profileDescription`
- `colorspace`
- `bitsPerSample`
- `autoStackId`
- `rating`
- `updatedAt`
- `updateId`

### 4.4 Bảng asset_file (đường dẫn preview/thumbnail/fullsize)

File:

- `server/src/schema/tables/asset-file.table.ts`

Các field:

- `id`
- `assetId`
- `createdAt`
- `updatedAt`
- `type`
- `path`
- `updateId`

Unique:

- `(assetId, type)`

### 4.5 Các bảng liên kết/hỗ trợ media

File:

- `server/src/schema/tables/stack.table.ts`
- `server/src/schema/tables/asset-face.table.ts`
- `server/src/schema/tables/album-asset.table.ts`
- `server/src/schema/tables/memory-asset.table.ts`
- `server/src/schema/tables/asset-metadata.table.ts`
- `server/src/schema/tables/asset-job-status.table.ts`
- `server/src/schema/tables/asset-ocr.table.ts`

Ý nghĩa nhanh:

- `stack`: nhóm ảnh, giữ `primaryAssetId`.
- `asset_face`: face box và mapping person.
- `album_asset`: mapping asset vào album.
- `memory_asset`: mapping asset vào memory.
- `asset_metadata`: metadata mở rộng dạng key/value.
- `asset_job_status`: trạng thái xử lý jobs (metadata/thumbnail/ocr...).
- `asset_ocr`: text box OCR theo asset.

## 5. Luồng Ghi/Đồng Bộ Dữ Liệu Ảnh/Video

### 5.1 Server upload và tạo asset

File:

- `server/src/services/asset-media.service.ts`
- `server/src/repositories/asset.repository.ts`

Luồng:

1. Upload file gọi `create()` trong `AssetMediaService`.
2. Ghi vào bảng `asset` qua `assetRepository.create(...)`.
3. Ghi `asset_exif.fileSizeInByte` ban đầu qua `upsertExif(...)`.
4. Đẩy job `AssetExtractMetadata`.

### 5.2 Metadata extraction (server)

File:

- `server/src/services/metadata.service.ts`

Luồng:

1. Job `AssetExtractMetadata` đọc EXIF.
2. Upsert vào `asset_exif` (camera/gps/date/rating...).
3. Update lại `asset` (`duration`, `localDateTime`, `fileCreatedAt`, `fileModifiedAt`).
4. Ghi `asset_job_status.metadataExtractedAt`.
5. Có thể link live photo (`livePhotoVideoId`) và ẩn motion asset.

### 5.3 Sinh thumbnail/preview/fullsize (server)

File:

- `server/src/services/media.service.ts`
- `server/src/repositories/asset.repository.ts` (`upsertFiles`, `update`)

Luồng:

1. Job thumbnail tạo file preview/thumbnail/fullsize.
2. Upsert vào `asset_file` (type + path).
3. Update `asset.thumbhash`.
4. Upsert `asset_job_status.previewAt`, `thumbnailAt`.

### 5.4 Remote sync stream về mobile Drift

File:

- `mobile/lib/domain/services/sync_stream.service.dart`
- `mobile/lib/infrastructure/repositories/sync_stream.repository.dart`

Luồng:

1. Nhận event `assetV1` và upsert `remote_asset_entity`.
2. Nhận `assetExifV1` và upsert `remote_exif_entity`, đồng thời update `remote_asset_entity.width/height`.
3. Nhận event album/stack/person/face và upsert bảng relation tương ứng.
4. Event delete/restore có kết hợp local trash flow trên Android.

### 5.5 Device local sync về bảng local Drift

File:

- `mobile/lib/domain/services/local_sync.service.dart`
- `mobile/lib/infrastructure/repositories/local_album.repository.dart`
- `mobile/lib/infrastructure/repositories/local_asset.repository.dart`
- `mobile/lib/infrastructure/repositories/trashed_local_asset.repository.dart`

Luồng:

1. Lấy album/asset từ native API.
2. Upsert vào `local_asset_entity` và mapping `local_album_asset_entity`.
3. `checksum` được cập nhật sau qua `updateHashes`.
4. Xử lý snapshot/restore local trash trong `trashed_local_asset_entity`.

## 6. Luồng Lấy Dữ Liệu Hiển Thị (Timeline)

### 6.1 Drift timeline (luồng mới)

File:

- `mobile/lib/infrastructure/repositories/timeline.repository.dart`
- `mobile/lib/infrastructure/entities/merged_asset.drift`

Query chính:

- `main()`: hợp nhất remote + local theo `checksum`.
- `remote()`, `favorite()`, `trash()`, `archived()`, `locked()`.
- `videoWithLocal()`, `videoLocal()`.
- `place()`: join theo `remote_exif_entity.city`.
- `person()`: join theo `asset_face_entity.personId`.
- `map()`: join theo tọa độ `remote_exif_entity`.

### 6.2 Isar timeline (legacy)

File:

- `mobile/lib/repositories/timeline.repository.dart`

Vẫn đọc timeline từ `db.assets` cho các mode như favorite/trash/video/home/multi-user/locked.

## 7. Mapping Field Quan Trọng Giữa Các Lớp

Một số mapping hay gặp:

- `checksum`:
  - Server: `asset.checksum`
  - Drift: `remote_asset_entity.checksum`, `local_asset_entity.checksum`
  - Isar: `Asset.checksum`
  - Vai trò: merge local-remote, chống trùng.

- Field thời gian tạo:
  - Server: `fileCreatedAt`, `localDateTime`
  - Drift: `createdAt`, `localDateTime` (remote)
  - Isar: `fileCreatedAt`

- Kích thước và dimensions:
  - Server: `asset_exif.exifImageWidth/exifImageHeight`, `asset_exif.fileSizeInByte`
  - Drift: `remote_asset_entity.width/height`, `remote_exif_entity.width/height/fileSize`
  - Isar: `Asset.width/height`, `ExifInfo.fileSize`

- Thumbnail hash:
  - Server: `asset.thumbhash`
  - Drift: `remote_asset_entity.thumbHash`
  - Isar: `Asset.thumbhash`

- Soft delete/trash:
  - Server: `asset.deletedAt`, `asset.status`
  - Drift: `remote_asset_entity.deletedAt`, `trashed_local_asset_entity`
  - Isar: `Asset.isTrashed`

## 8. Checklist Khi Thêm/Sửa Field Mới

Để không vỡ luồng khi thêm/sửa field media:

1. Server schema:
   - Sửa table trong `server/src/schema/tables/...`.
   - Tạo migration.
2. Server repository/service:
   - Update `asset.repository.ts` (create/update/upsert/select).
   - Update service liên quan (`asset-media`, `metadata`, `media`, `asset`).
3. Sync payload:
   - Đảm bảo field đi vào stream (`assetV1`, `assetExifV1`) nếu cần realtime trên client.
4. Mobile Drift:
   - Sửa entity trong `mobile/lib/infrastructure/entities/...`.
   - Update migration (`schemaVersion` + migration step) trong `db.repository.dart`.
   - Update logic ghi/đọc ở `sync_stream.repository.dart`, `remote_asset.repository.dart`.
   - Update timeline query nếu field tham gia filter/sort/group.
5. Mobile Isar (nếu luồng cũ còn dùng field đó):
   - Sửa `mobile/lib/entities/asset.entity.dart` hoặc `ExifInfo`.
   - Sửa `sync.service.dart` và repository Isar liên quan.
6. Verify:
   - Kiểm tra luồng create/upload, metadata extraction, sync stream, timeline read, trash/restore.

## 9. Index File Quan Trọng

### Mobile Drift

- `mobile/lib/infrastructure/repositories/db.repository.dart`
- `mobile/lib/infrastructure/entities/local_asset.entity.dart`
- `mobile/lib/infrastructure/entities/remote_asset.entity.dart`
- `mobile/lib/infrastructure/entities/trashed_local_asset.entity.dart`
- `mobile/lib/infrastructure/entities/exif.entity.dart`
- `mobile/lib/infrastructure/entities/merged_asset.drift`
- `mobile/lib/infrastructure/repositories/timeline.repository.dart`
- `mobile/lib/infrastructure/repositories/remote_asset.repository.dart`
- `mobile/lib/infrastructure/repositories/local_asset.repository.dart`
- `mobile/lib/infrastructure/repositories/trashed_local_asset.repository.dart`
- `mobile/lib/infrastructure/repositories/sync_stream.repository.dart`
- `mobile/lib/domain/services/sync_stream.service.dart`
- `mobile/lib/domain/services/local_sync.service.dart`

### Mobile Isar

- `mobile/lib/entities/asset.entity.dart`
- `mobile/lib/infrastructure/entities/exif.entity.dart`
- `mobile/lib/repositories/asset.repository.dart`
- `mobile/lib/repositories/timeline.repository.dart`
- `mobile/lib/services/sync.service.dart`

### Server Postgres

- `server/src/schema/index.ts`
- `server/src/schema/tables/asset.table.ts`
- `server/src/schema/tables/asset-exif.table.ts`
- `server/src/schema/tables/asset-file.table.ts`
- `server/src/schema/tables/stack.table.ts`
- `server/src/schema/tables/asset-face.table.ts`
- `server/src/schema/tables/asset-metadata.table.ts`
- `server/src/schema/tables/asset-job-status.table.ts`
- `server/src/schema/tables/asset-ocr.table.ts`
- `server/src/repositories/asset.repository.ts`
- `server/src/services/asset-media.service.ts`
- `server/src/services/metadata.service.ts`
- `server/src/services/media.service.ts`
- `server/src/services/asset.service.ts`
