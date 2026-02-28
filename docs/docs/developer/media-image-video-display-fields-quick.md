---
title: Field Hiển Thị Ảnh Video (Tóm Tắt Nhanh)
---

# Field Hiển Thị Ảnh/Video (Tóm Tắt Nhanh)

Tài liệu này là bản rút gọn từ tài liệu chi tiết, chỉ tập trung vào:

- Các field cần có để hiển thị ảnh/video.
- Các field code hiện tại đang lấy để render UI.
- Ý nghĩa nhanh của từng nhóm field.

## 1. Bộ Field Tối Thiểu Để Render Thumbnail Timeline

Đây là nhóm field nên xem là “bắt buộc” nếu muốn tile ảnh/video hiển thị đúng:

| Field | Mục đích hiển thị | Bắt buộc |
|---|---|---|
| `id` (`remoteId` hoặc `localId`) | Định danh asset, mở viewer, load thumbnail | Có |
| `type` | Phân biệt ảnh/video để hiện icon/video controls | Có |
| `createdAt` | Group timeline theo ngày/tháng, scroll-to-date | Có |
| `durationInSeconds` | Hiện thời lượng khi là video | Có (với video) |
| `isFavorite` | Hiện icon yêu thích trên tile | Có |
| `livePhotoVideoId` | Hiện trạng thái motion/live photo | Nên có |
| `stackId` (remote) | Hiện icon stack/burst | Nên có |
| `thumbHash` (remote) | Placeholder mượt khi chưa tải thumbnail thật | Nên có |
| `localId`/`remoteId` | Chọn nguồn ảnh local hay remote | Có |

Nguồn code chính:

- `mobile/lib/presentation/widgets/images/thumbnail_tile.widget.dart`
- `mobile/lib/presentation/widgets/images/thumbnail.widget.dart`
- `mobile/lib/presentation/widgets/images/image_provider.dart`

## 2. Field Mở Rộng Khi Mở Asset Viewer

Khi mở màn xem ảnh/video, code dùng thêm các field sau:

| Field | Dùng để làm gì |
|---|---|
| `ownerId` (remote) | Kiểm tra quyền chủ sở hữu để hiện action (favorite/delete/edit...) |
| `visibility` (remote) | Xác định trạng thái archive/locked |
| `width`, `height` | Tính tỉ lệ hiển thị (aspect ratio), hiển thị thông tin kích thước |
| `orientation` (local) + EXIF orientation | Sửa hướng ảnh/tỉ lệ đúng chiều |
| `name` | Hiển thị tên file trong sheet chi tiết |
| `storage` (derive) | Hiện icon cloud local/remote/merged |

Nguồn code chính:

- `mobile/lib/presentation/widgets/asset_viewer/top_app_bar.widget.dart`
- `mobile/lib/presentation/widgets/asset_viewer/bottom_bar.widget.dart`
- `mobile/lib/presentation/widgets/asset_viewer/video_viewer.widget.dart`
- `mobile/lib/presentation/widgets/asset_viewer/bottom_sheet.widget.dart`

## 3. Field EXIF Dùng Cho Sheet Chi Tiết

Các field này không luôn load cùng timeline, thường được lấy thêm theo `assetId` khi mở viewer:

| Field EXIF | Ý nghĩa hiển thị |
|---|---|
| `fileSize` | Dung lượng file |
| `description` | Mô tả ảnh/video |
| `dateTimeOriginal`, `timeZone` | Thời gian gốc |
| `latitude`, `longitude` | Tọa độ bản đồ |
| `city`, `state`, `country` | Địa điểm |
| `make`, `model` | Hãng/model camera |
| `lens` | Ống kính |
| `f`, `mm`, `iso`, `exposureSeconds` | Thông số chụp |
| `orientation` | Hướng ảnh |

Nguồn code chính:

- `mobile/lib/providers/infrastructure/asset_viewer/current_asset.provider.dart`
- `mobile/lib/domain/services/asset.service.dart`
- `mobile/lib/presentation/widgets/asset_viewer/bottom_sheet.widget.dart`
- `mobile/lib/presentation/widgets/asset_viewer/bottom_sheet/sheet_location_details.widget.dart`

## 4. Hiện Tại Timeline Query Đang Lấy Những Field Nào

### 4.1 Luồng `main()` và `videoWithLocal()`

Các query custom SQL đang map về `RemoteAsset`/`LocalAsset` với các cột:

- `remote_id`
- `local_id`
- `name`
- `type`
- `created_at`
- `updated_at`
- `width`
- `height`
- `duration_in_seconds`
- `is_favorite`
- `thumb_hash`
- `checksum`
- `owner_id`
- `live_photo_video_id`
- `orientation`
- `stack_id`

Nguồn:

- `mobile/lib/infrastructure/entities/merged_asset.drift`
- `mobile/lib/infrastructure/repositories/timeline.repository.dart`

### 4.2 Luồng remote-only (`remote/favorite/trash/archive/locked/video/place/person/map`)

Nhóm này đọc từ `remote_asset_entity` và map về `RemoteAsset`, thực tế dùng các field:

- `id`
- `name`
- `ownerId`
- `checksum`
- `type`
- `createdAt`
- `updatedAt`
- `durationInSeconds`
- `isFavorite`
- `width`
- `height`
- `thumbHash`
- `visibility`
- `livePhotoVideoId`
- `stackId`
- (`localId` nếu có join với local để biết merged)

Nguồn:

- `mobile/lib/infrastructure/repositories/timeline.repository.dart`
- `mobile/lib/domain/models/asset/remote_asset.model.dart`

### 4.3 Luồng local-only (`localAlbum`, `videoLocal`)

Map về `LocalAsset` với các field:

- `id`
- `name`
- `checksum`
- `type`
- `createdAt`
- `updatedAt`
- `width`
- `height`
- `durationInSeconds`
- `isFavorite`
- `orientation`
- (`remoteId` nếu có liên kết checksum)

Nguồn:

- `mobile/lib/infrastructure/repositories/timeline.repository.dart`
- `mobile/lib/domain/models/asset/local_asset.model.dart`

## 5. Ý Nghĩa Nhanh Theo Nhóm

### Nhóm nhận diện và nguồn dữ liệu

- `id`, `localId`, `remoteId`, `checksum`, `storage`
- Mục tiêu: xác định asset, phân biệt local/remote/merged, chọn nguồn load media.

### Nhóm hiển thị tile

- `type`, `durationInSeconds`, `isFavorite`, `stackId`, `livePhotoVideoId`, `thumbHash`
- Mục tiêu: icon video, thời lượng, favorite, stack, live photo, placeholder.

### Nhóm thời gian và phân nhóm timeline

- `createdAt` (chính), `updatedAt` (phụ)
- Mục tiêu: group theo ngày/tháng, điều hướng tới ngày tương ứng.

### Nhóm metadata cho viewer chi tiết

- `name`, `width`, `height`, EXIF fields
- Mục tiêu: hiển thị thông tin file/camera/location và aspect ratio.

## 6. Checklist Nhanh Khi Thêm Field Mới Cho UI

1. Thêm vào model phù hợp (`BaseAsset`/`LocalAsset`/`RemoteAsset`) nếu field cần dùng trực tiếp ở UI.
2. Đảm bảo query timeline map ra field đó (`timeline.repository.dart` hoặc `merged_asset.drift`).
3. Nếu là EXIF chi tiết, đảm bảo `AssetService.getExif()` và provider `currentAssetExifProvider` lấy được.
4. Kiểm tra lại 3 màn: Timeline tile, Asset Viewer, Bottom Sheet.

