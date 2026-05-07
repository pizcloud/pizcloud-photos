import { join } from 'node:path';
import { StorageCore } from 'src/cores/storage.core';
import { AssetUploadSessionStatus } from 'src/dtos/asset-media-response.dto';
import { AssetUploadSessionCreateDto } from 'src/dtos/asset-media.dto';
import { AuthDto } from 'src/dtos/auth.dto';
import { StorageFolder } from 'src/enum';
import { AssetMediaService } from 'src/services/asset-media.service';
import { AssetUploadSessionService } from 'src/services/asset-upload-session.service';
import { authStub } from 'test/fixtures/auth.stub';
import { newStorageRepositoryMock } from 'test/repositories/storage.repository.mock';
import { Mocked, vi } from 'vitest';

const makeCreateDto = (overrides: Partial<AssetUploadSessionCreateDto> = {}): AssetUploadSessionCreateDto =>
  ({
    deviceAssetId: 'device-asset-id',
    deviceId: 'WEB',
    fileCreatedAt: new Date('2026-01-01T00:00:00.000Z'),
    fileModifiedAt: new Date('2026-01-01T00:00:00.000Z'),
    isFavorite: false,
    duration: '0:00:00.000000',
    fileName: 'video.webm',
    fileSize: 300,
    chunkSize: 300,
    totalChunks: 1,
    ...overrides,
  }) as AssetUploadSessionCreateDto;

const makeAuthWithQuota = ({
  quotaSizeInBytes,
  quotaUsageInBytes,
}: {
  quotaSizeInBytes: number | null;
  quotaUsageInBytes: number;
}): AuthDto =>
  ({
    ...authStub.user1,
    user: {
      ...authStub.user1.user,
      quotaSizeInBytes,
      quotaUsageInBytes,
    },
  }) as AuthDto;

describe(AssetUploadSessionService.name, () => {
  let sut: AssetUploadSessionService;
  let storage: ReturnType<typeof newStorageRepositoryMock>;
  let assetMediaService: Mocked<Pick<AssetMediaService, 'getUploadAssetIdByChecksum'>>;

  beforeEach(() => {
    storage = newStorageRepositoryMock();
    storage.existsSync.mockReturnValue(false);

    assetMediaService = {
      getUploadAssetIdByChecksum: vi.fn().mockResolvedValue(undefined),
    } as unknown as Mocked<Pick<AssetMediaService, 'getUploadAssetIdByChecksum'>>;

    const logger = {
      setContext: vi.fn(),
      warn: vi.fn(),
      debug: vi.fn(),
      log: vi.fn(),
      error: vi.fn(),
    };

    sut = new AssetUploadSessionService(logger as any, storage as any, assetMediaService as any);
  });

  it('should reject create when quota + reserved + requested exceeds limit', async () => {
    const auth = makeAuthWithQuota({ quotaSizeInBytes: 1000, quotaUsageInBytes: 400 });
    const dto = makeCreateDto({ fileSize: 300, chunkSize: 300, totalChunks: 1 });

    const sessionRootPath = join(StorageCore.getFolderLocation(StorageFolder.Upload, auth.user.id), 'resumable-sessions');
    const existingSessionId = 'session-a';
    const existingManifestPath = join(sessionRootPath, existingSessionId, 'session.json');

    storage.existsSync.mockImplementation((path) => path === sessionRootPath || path === existingManifestPath);
    storage.readdir.mockResolvedValue([existingSessionId]);
    storage.stat.mockResolvedValue({ isDirectory: () => true } as any);
    storage.readTextFile.mockResolvedValue(
      JSON.stringify({ id: existingSessionId, userId: auth.user.id, fileSize: 400 }),
    );

    await expect(sut.create(auth, dto)).rejects.toThrow('Quota has been exceeded!');
    expect(assetMediaService.getUploadAssetIdByChecksum).not.toHaveBeenCalled();
    expect(storage.createOrOverwriteFile).not.toHaveBeenCalled();
  });

  it('should allow create when projected usage equals quota', async () => {
    const auth = makeAuthWithQuota({ quotaSizeInBytes: 1000, quotaUsageInBytes: 400 });
    const dto = makeCreateDto({ fileSize: 300, chunkSize: 300, totalChunks: 1 });

    const sessionRootPath = join(StorageCore.getFolderLocation(StorageFolder.Upload, auth.user.id), 'resumable-sessions');
    const existingSessionId = 'session-b';
    const existingManifestPath = join(sessionRootPath, existingSessionId, 'session.json');

    storage.existsSync.mockImplementation((path) => path === sessionRootPath || path === existingManifestPath);
    storage.readdir.mockResolvedValue([existingSessionId]);
    storage.stat.mockResolvedValue({ isDirectory: () => true } as any);
    storage.readTextFile.mockResolvedValue(
      JSON.stringify({ id: existingSessionId, userId: auth.user.id, fileSize: 300 }),
    );

    const result = await sut.create(auth, dto);
    expect(result.status).toBe(AssetUploadSessionStatus.ACTIVE);
    expect(assetMediaService.getUploadAssetIdByChecksum).toHaveBeenCalled();
    expect(storage.mkdirSync).toHaveBeenCalled();
    expect(storage.createOrOverwriteFile).toHaveBeenCalled();
  });

  it('should ignore malformed manifests while calculating reserved bytes', async () => {
    const auth = makeAuthWithQuota({ quotaSizeInBytes: 1000, quotaUsageInBytes: 800 });
    const dto = makeCreateDto({ fileSize: 100, chunkSize: 100, totalChunks: 1 });

    const sessionRootPath = join(StorageCore.getFolderLocation(StorageFolder.Upload, auth.user.id), 'resumable-sessions');
    const invalidSessionId = 'session-invalid';
    const validSessionId = 'session-valid';
    const invalidManifestPath = join(sessionRootPath, invalidSessionId, 'session.json');
    const validManifestPath = join(sessionRootPath, validSessionId, 'session.json');

    storage.existsSync.mockImplementation((path) => {
      return path === sessionRootPath || path === invalidManifestPath || path === validManifestPath;
    });
    storage.readdir.mockResolvedValue([invalidSessionId, validSessionId]);
    storage.stat.mockResolvedValue({ isDirectory: () => true } as any);
    storage.readTextFile.mockImplementation(async (path) => {
      if (path === invalidManifestPath) {
        return '{invalid-json';
      }

      if (path === validManifestPath) {
        return JSON.stringify({ id: validSessionId, userId: auth.user.id, fileSize: 100 });
      }

      return '{}';
    });

    const result = await sut.create(auth, dto);
    expect(result.status).toBe(AssetUploadSessionStatus.ACTIVE);
    expect(storage.createOrOverwriteFile).toHaveBeenCalled();
  });
});
