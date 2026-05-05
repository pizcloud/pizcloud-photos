import { ValidateEnum } from 'src/validation';

export enum AssetMediaStatus {
  CREATED = 'created',
  REPLACED = 'replaced',
  DUPLICATE = 'duplicate',
}
export class AssetMediaResponseDto {
  @ValidateEnum({ enum: AssetMediaStatus, name: 'AssetMediaStatus' })
  status!: AssetMediaStatus;
  id!: string;
}

export enum AssetUploadAction {
  ACCEPT = 'accept',
  REJECT = 'reject',
}

export enum AssetRejectReason {
  DUPLICATE = 'duplicate',
  UNSUPPORTED_FORMAT = 'unsupported-format',
}

export class AssetBulkUploadCheckResult {
  id!: string;
  action!: AssetUploadAction;
  reason?: AssetRejectReason;
  assetId?: string;
  isTrashed?: boolean;
}

export class AssetBulkUploadCheckResponseDto {
  results!: AssetBulkUploadCheckResult[];
}

export class CheckExistingAssetsResponseDto {
  existingIds!: string[];
}

// pizcloud
export enum AssetUploadSessionStatus {
  ACTIVE = 'active',
  COMPLETED = 'completed',
  DUPLICATE = 'duplicate',
  DELETED = 'deleted',
}

export class AssetUploadSessionCreateResponseDto {
  status!: AssetUploadSessionStatus.ACTIVE | AssetUploadSessionStatus.DUPLICATE;
  id?: string;
  assetId?: string;
  isTrashed?: boolean;
  chunkSize?: number;
  totalChunks?: number;
  uploadedChunks?: number[];
}

export class AssetUploadSessionStatusResponseDto {
  status!: AssetUploadSessionStatus;
  id!: string;
  chunkSize!: number;
  totalChunks!: number;
  fileSize!: number;
  uploadedChunks!: number[];
}

export class AssetUploadSessionChunkResponseDto {
  id!: string;
  chunkIndex!: number;
  uploadedChunks!: number[];
}

export class AssetUploadSessionDeleteResponseDto {
  status!: AssetUploadSessionStatus.DELETED;
  id!: string;
}
// #pizcloud
