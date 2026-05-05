import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Request } from 'express';
import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { StorageCore } from 'src/cores/storage.core';
import {
  AssetMediaResponseDto,
  AssetUploadSessionChunkResponseDto,
  AssetUploadSessionCreateResponseDto,
  AssetUploadSessionDeleteResponseDto,
  AssetUploadSessionStatus,
  AssetUploadSessionStatusResponseDto,
} from 'src/dtos/asset-media-response.dto';
import { AssetMediaCreateDto, AssetUploadSessionCreateDto, UploadFieldName } from 'src/dtos/asset-media.dto';
import { AuthDto } from 'src/dtos/auth.dto';
import { StorageFolder } from 'src/enum';
import { LoggingRepository } from 'src/repositories/logging.repository';
import { StorageRepository } from 'src/repositories/storage.repository';
import { AssetMediaService } from 'src/services/asset-media.service';
import { UploadFile, UploadRequest } from 'src/types';
import { fromChecksum } from 'src/utils/request';

interface PersistedAssetMediaCreate {
  deviceAssetId: string;
  deviceId: string;
  fileCreatedAt: string;
  fileModifiedAt: string;
  duration?: string;
  filename?: string;
  isFavorite?: boolean;
  visibility?: string;
  livePhotoVideoId?: string;
  metadata?: AssetMediaCreateDto['metadata'];
}

interface AssetUploadSessionManifest {
  id: string;
  userId: string;
  createdAt: string;
  updatedAt: string;
  status: AssetUploadSessionStatus.ACTIVE | AssetUploadSessionStatus.COMPLETED;
  fileName: string;
  fileSize: number;
  chunkSize: number;
  totalChunks: number;
  checksum?: string;
  uploadedChunks: number[];
  asset: PersistedAssetMediaCreate;
}

@Injectable()
export class AssetUploadSessionService {
  private readonly sessionRootFolder = 'resumable-sessions';

  constructor(
    private readonly logger: LoggingRepository,
    private readonly storageRepository: StorageRepository,
    private readonly assetMediaService: AssetMediaService,
  ) {
    this.logger.setContext(AssetUploadSessionService.name);
  }

  async create(auth: AuthDto, dto: AssetUploadSessionCreateDto): Promise<AssetUploadSessionCreateResponseDto> {
    this.validateChunkLayout(dto.fileSize, dto.chunkSize, dto.totalChunks);
    this.requireQuota(auth, dto.fileSize);

    const checksum = this.normalizeChecksum(dto.checksum);
    const duplicate = await this.assetMediaService.getUploadAssetIdByChecksum(auth, checksum);
    if (duplicate) {
      return {
        status: AssetUploadSessionStatus.DUPLICATE,
        assetId: duplicate.id,
      };
    }

    const id = randomUUID();
    const now = new Date().toISOString();

    const manifest: AssetUploadSessionManifest = {
      id,
      userId: auth.user.id,
      createdAt: now,
      updatedAt: now,
      status: AssetUploadSessionStatus.ACTIVE,
      fileName: dto.fileName,
      fileSize: dto.fileSize,
      chunkSize: dto.chunkSize,
      totalChunks: dto.totalChunks,
      checksum,
      uploadedChunks: [],
      asset: this.toPersistedAsset(dto),
    };

    this.storageRepository.mkdirSync(this.getSessionChunkDirPath(auth.user.id, id));
    await this.persistSession(auth.user.id, manifest);

    return {
      status: AssetUploadSessionStatus.ACTIVE,
      id,
      chunkSize: manifest.chunkSize,
      totalChunks: manifest.totalChunks,
      uploadedChunks: manifest.uploadedChunks,
    };
  }

  async getStatus(auth: AuthDto, id: string): Promise<AssetUploadSessionStatusResponseDto> {
    const manifest = await this.getSession(auth.user.id, id);
    const missing = this.getMissingChunkIndexes(manifest);

    return {
      status: missing.length === 0 ? AssetUploadSessionStatus.COMPLETED : manifest.status,
      id: manifest.id,
      chunkSize: manifest.chunkSize,
      totalChunks: manifest.totalChunks,
      fileSize: manifest.fileSize,
      uploadedChunks: manifest.uploadedChunks,
    };
  }

  async uploadChunk(
    auth: AuthDto,
    id: string,
    chunkIndex: number,
    request: Request,
  ): Promise<AssetUploadSessionChunkResponseDto> {
    const manifest = await this.getSession(auth.user.id, id);

    if (!Number.isInteger(chunkIndex) || chunkIndex < 0 || chunkIndex >= manifest.totalChunks) {
      throw new BadRequestException(`chunkIndex must be between 0 and ${manifest.totalChunks - 1}`);
    }

    const expectedChunkSize = this.getExpectedChunkSize(manifest, chunkIndex);
    const contentLength = this.getContentLength(request);
    if (contentLength !== null && contentLength !== expectedChunkSize) {
      throw new BadRequestException(
        `Invalid chunk size for index ${chunkIndex}. Expected ${expectedChunkSize} bytes but got ${contentLength}`,
      );
    }

    const chunkPath = this.getChunkPath(auth.user.id, id, chunkIndex);
    this.storageRepository.mkdirSync(dirname(chunkPath));
    if (this.storageRepository.existsSync(chunkPath)) {
      await this.storageRepository.unlink(chunkPath);
    }

    await pipeline(request, this.storageRepository.createWriteStream(chunkPath));

    const { size } = await this.storageRepository.stat(chunkPath);
    if (size !== expectedChunkSize) {
      await this.storageRepository.unlink(chunkPath);
      throw new BadRequestException(
        `Invalid chunk payload for index ${chunkIndex}. Expected ${expectedChunkSize} bytes but got ${size}`,
      );
    }

    manifest.uploadedChunks = this.normalizeUploadedChunks(
      [...manifest.uploadedChunks, chunkIndex],
      manifest.totalChunks,
    );
    manifest.status =
      this.getMissingChunkIndexes(manifest).length === 0 ? AssetUploadSessionStatus.COMPLETED : manifest.status;
    await this.persistSession(auth.user.id, manifest);

    return {
      id,
      chunkIndex,
      uploadedChunks: manifest.uploadedChunks,
    };
  }

  async complete(auth: AuthDto, id: string): Promise<AssetMediaResponseDto> {
    const manifest = await this.getSession(auth.user.id, id);
    const missing = this.getMissingChunkIndexes(manifest);
    if (missing.length > 0) {
      throw new BadRequestException(`Missing chunks: ${missing.slice(0, 20).join(', ')}`);
    }

    await this.ensureAllChunkFiles(manifest);

    const uploadFile = await this.mergeChunksToUploadFile(auth, manifest);

    if (manifest.checksum && manifest.checksum !== uploadFile.checksum.toString('hex')) {
      await this.storageRepository.unlink(uploadFile.originalPath);
      throw new BadRequestException('Checksum mismatch while completing upload session');
    }

    try {
      const result = await this.assetMediaService.uploadAsset(auth, this.toAssetCreateDto(manifest.asset), uploadFile);
      await this.storageRepository.unlinkDir(this.getSessionDirPath(auth.user.id, id), {
        recursive: true,
        force: true,
      });
      return result;
    } catch (error) {
      await this.storageRepository.unlink(uploadFile.originalPath);
      throw error;
    }
  }

  async delete(auth: AuthDto, id: string): Promise<AssetUploadSessionDeleteResponseDto> {
    await this.getSession(auth.user.id, id);
    await this.storageRepository.unlinkDir(this.getSessionDirPath(auth.user.id, id), { recursive: true, force: true });
    return { status: AssetUploadSessionStatus.DELETED, id };
  }

  private getSessionDirPath(userId: string, id: string) {
    return join(StorageCore.getFolderLocation(StorageFolder.Upload, userId), this.sessionRootFolder, id);
  }

  private getSessionChunkDirPath(userId: string, id: string) {
    return join(this.getSessionDirPath(userId, id), 'chunks');
  }

  private getSessionManifestPath(userId: string, id: string) {
    return join(this.getSessionDirPath(userId, id), 'session.json');
  }

  private getChunkPath(userId: string, id: string, chunkIndex: number) {
    return join(this.getSessionChunkDirPath(userId, id), `${chunkIndex}.part`);
  }

  private async getSession(userId: string, id: string): Promise<AssetUploadSessionManifest> {
    const manifestPath = this.getSessionManifestPath(userId, id);
    if (!this.storageRepository.existsSync(manifestPath)) {
      throw new NotFoundException('Upload session not found');
    }

    let manifest: AssetUploadSessionManifest;
    try {
      const raw = await this.storageRepository.readTextFile(manifestPath);
      manifest = JSON.parse(raw) as AssetUploadSessionManifest;
    } catch (error) {
      this.logger.error(`Failed to read upload session ${id}: ${error}`);
      throw new NotFoundException('Upload session not found');
    }

    if (manifest.id !== id || manifest.userId !== userId) {
      throw new NotFoundException('Upload session not found');
    }

    if (
      !Number.isInteger(manifest.fileSize) ||
      !Number.isInteger(manifest.chunkSize) ||
      !Number.isInteger(manifest.totalChunks) ||
      manifest.fileSize < 1 ||
      manifest.chunkSize < 1 ||
      manifest.totalChunks < 1
    ) {
      throw new NotFoundException('Upload session not found');
    }

    manifest.uploadedChunks = this.normalizeUploadedChunks(manifest.uploadedChunks ?? [], manifest.totalChunks);
    return manifest;
  }

  private async persistSession(userId: string, manifest: AssetUploadSessionManifest) {
    manifest.updatedAt = new Date().toISOString();
    const path = this.getSessionManifestPath(userId, manifest.id);
    const buffer = Buffer.from(JSON.stringify(manifest), 'utf8');
    await this.storageRepository.createOrOverwriteFile(path, buffer);
  }

  private toPersistedAsset(dto: AssetUploadSessionCreateDto): PersistedAssetMediaCreate {
    return {
      deviceAssetId: dto.deviceAssetId,
      deviceId: dto.deviceId,
      fileCreatedAt: dto.fileCreatedAt.toISOString(),
      fileModifiedAt: dto.fileModifiedAt.toISOString(),
      duration: dto.duration,
      filename: dto.filename,
      isFavorite: dto.isFavorite,
      visibility: dto.visibility,
      livePhotoVideoId: dto.livePhotoVideoId,
      metadata: dto.metadata,
    };
  }

  private toAssetCreateDto(asset: PersistedAssetMediaCreate): AssetMediaCreateDto {
    return {
      ...asset,
      fileCreatedAt: new Date(asset.fileCreatedAt),
      fileModifiedAt: new Date(asset.fileModifiedAt),
    } as AssetMediaCreateDto;
  }

  private getContentLength(request: Request): number | null {
    const value = request.header('content-length');
    if (!value) {
      return null;
    }

    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }

  private normalizeChecksum(checksum?: string): string | undefined {
    if (!checksum) {
      return undefined;
    }

    const value = checksum.trim();
    if (!value) {
      return undefined;
    }

    const isHex = /^[0-9a-fA-F]{40}$/.test(value);
    const isBase64 = /^[A-Za-z0-9+/]{27}=$/.test(value);
    if (!isHex && !isBase64) {
      throw new BadRequestException('checksum must be a valid SHA-1 hash in hex or base64 format');
    }

    return isHex ? value.toLowerCase() : fromChecksum(value).toString('hex');
  }

  private validateChunkLayout(fileSize: number, chunkSize: number, totalChunks: number) {
    const expected = Math.ceil(fileSize / chunkSize);
    if (expected !== totalChunks) {
      throw new BadRequestException(`totalChunks mismatch: expected ${expected}, got ${totalChunks}`);
    }
  }

  private getExpectedChunkSize(manifest: AssetUploadSessionManifest, chunkIndex: number): number {
    const isLast = chunkIndex === manifest.totalChunks - 1;
    if (!isLast) {
      return manifest.chunkSize;
    }

    const remaining = manifest.fileSize - manifest.chunkSize * (manifest.totalChunks - 1);
    return remaining > 0 ? remaining : manifest.chunkSize;
  }

  private normalizeUploadedChunks(chunks: number[], totalChunks: number): number[] {
    const filtered = chunks.filter((value) => Number.isInteger(value) && value >= 0 && value < totalChunks);
    return [...new Set(filtered)].toSorted((a, b) => a - b);
  }

  private getMissingChunkIndexes(manifest: AssetUploadSessionManifest): number[] {
    const uploaded = new Set(manifest.uploadedChunks);
    const missing: number[] = [];
    for (let chunkIndex = 0; chunkIndex < manifest.totalChunks; chunkIndex++) {
      if (!uploaded.has(chunkIndex)) {
        missing.push(chunkIndex);
      }
    }

    return missing;
  }

  private async ensureAllChunkFiles(manifest: AssetUploadSessionManifest) {
    for (let chunkIndex = 0; chunkIndex < manifest.totalChunks; chunkIndex++) {
      const chunkPath = this.getChunkPath(manifest.userId, manifest.id, chunkIndex);
      if (!this.storageRepository.existsSync(chunkPath)) {
        throw new BadRequestException(`Chunk file missing: ${basename(chunkPath)}`);
      }

      const expectedChunkSize = this.getExpectedChunkSize(manifest, chunkIndex);
      const { size } = await this.storageRepository.stat(chunkPath);
      if (size !== expectedChunkSize) {
        throw new BadRequestException(
          `Chunk file invalid at index ${chunkIndex}. Expected ${expectedChunkSize} bytes but got ${size}`,
        );
      }
    }
  }

  private async mergeChunksToUploadFile(auth: AuthDto, manifest: AssetUploadSessionManifest): Promise<UploadFile> {
    const uploadUuid = randomUUID();
    const uploadRequest: UploadRequest = {
      auth,
      fieldName: UploadFieldName.ASSET_DATA,
      file: {
        uuid: uploadUuid,
        checksum: Buffer.alloc(0),
        originalPath: '',
        originalName: manifest.fileName,
        size: manifest.fileSize,
      },
      body: { filename: manifest.asset.filename || manifest.fileName },
    };

    const uploadFolder = this.assetMediaService.getUploadFolder(uploadRequest);
    const uploadFilename = this.assetMediaService.getUploadFilename(uploadRequest);
    const uploadPath = join(uploadFolder, uploadFilename);

    const hash = createHash('sha1');
    const writeStream = this.storageRepository.createWriteStream(uploadPath);

    try {
      for (let chunkIndex = 0; chunkIndex < manifest.totalChunks; chunkIndex++) {
        const chunkPath = this.getChunkPath(manifest.userId, manifest.id, chunkIndex);

        for await (const chunk of createReadStream(chunkPath)) {
          const data = chunk as Buffer;
          hash.update(data);

          if (!writeStream.write(data)) {
            await new Promise<void>((resolve, reject) => {
              const onDrain = () => {
                cleanup();
                resolve();
              };
              const onError = (error: Error) => {
                cleanup();
                reject(error);
              };
              const cleanup = () => {
                writeStream.off('drain', onDrain);
                writeStream.off('error', onError);
              };

              writeStream.on('drain', onDrain);
              writeStream.on('error', onError);
            });
          }
        }
      }

      await new Promise<void>((resolve, reject) => {
        writeStream.once('error', reject);
        writeStream.end(() => resolve());
      });
    } catch (error) {
      writeStream.destroy();
      throw error;
    }

    return {
      uuid: uploadUuid,
      checksum: hash.digest(),
      originalPath: uploadPath,
      originalName: manifest.fileName,
      size: manifest.fileSize,
    };
  }

  private requireQuota(auth: AuthDto, size: number) {
    if (auth.user.quotaSizeInBytes !== null && auth.user.quotaSizeInBytes < auth.user.quotaUsageInBytes + size) {
      throw new BadRequestException('Quota has been exceeded!');
    }
  }
}
