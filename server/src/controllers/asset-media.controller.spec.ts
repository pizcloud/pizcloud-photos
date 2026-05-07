import { AssetMediaController } from 'src/controllers/asset-media.controller';
import { AssetMediaStatus, AssetUploadSessionStatus } from 'src/dtos/asset-media-response.dto';
import { AssetMetadataKey } from 'src/enum';
import { LoggingRepository } from 'src/repositories/logging.repository';
import { AssetMediaService } from 'src/services/asset-media.service';
import { AssetUploadSessionService } from 'src/services/asset-upload-session.service';
import request from 'supertest';
import { factory } from 'test/small.factory';
import { automock, ControllerContext, controllerSetup, mockBaseService } from 'test/utils';

const makeUploadDto = (options?: { omit: string }): Record<string, any> => {
  const dto: Record<string, any> = {
    deviceAssetId: 'example-image',
    deviceId: 'TEST',
    fileCreatedAt: new Date().toISOString(),
    fileModifiedAt: new Date().toISOString(),
    isFavorite: 'false',
    duration: '0:00:00.000000',
  };

  const omit = options?.omit;
  if (omit) {
    delete dto[omit];
  }

  return dto;
};

describe(AssetMediaController.name, () => {
  let ctx: ControllerContext;
  const assetData = Buffer.from('123');
  const filename = 'example.png';
  const service = mockBaseService(AssetMediaService);
  const uploadSessionService = automock(AssetUploadSessionService, {
    args: [{ setContext: () => {} } as any, {} as any, {} as any],
    strict: false,
  });

  beforeAll(async () => {
    ctx = await controllerSetup(AssetMediaController, [
      { provide: LoggingRepository, useValue: automock(LoggingRepository, { strict: false }) },
      { provide: AssetMediaService, useValue: service },
      { provide: AssetUploadSessionService, useValue: uploadSessionService },
    ]);
    return () => ctx.close();
  });

  beforeEach(() => {
    service.resetAllMocks();
    uploadSessionService.resetAllMocks();
    service.uploadAsset.mockResolvedValue({ status: AssetMediaStatus.DUPLICATE, id: factory.uuid() });
    uploadSessionService.create.mockResolvedValue({
      status: AssetUploadSessionStatus.ACTIVE,
      id: factory.uuid(),
      chunkSize: 8_388_608,
      totalChunks: 1,
      uploadedChunks: [],
    });
    uploadSessionService.uploadChunk.mockResolvedValue({ id: factory.uuid(), chunkIndex: 0, uploadedChunks: [0] });

    ctx.reset();
  });

  describe('POST /assets', () => {
    it('should be an authenticated route', async () => {
      await request(ctx.getHttpServer()).post(`/assets`);
      expect(ctx.authenticate).toHaveBeenCalled();
    });

    it('should accept metadata', async () => {
      const mobileMetadata = { key: AssetMetadataKey.MobileApp, value: { iCloudId: '123' } };
      const { status } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({
          ...makeUploadDto(),
          metadata: JSON.stringify([mobileMetadata]),
        });

      expect(service.uploadAsset).toHaveBeenCalledWith(
        undefined,
        expect.objectContaining({ metadata: [mobileMetadata] }),
        expect.objectContaining({ originalName: 'example.png' }),
        undefined,
      );

      expect(status).toBe(200);
    });

    it('should handle invalid metadata json', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({
          ...makeUploadDto(),
          metadata: 'not-a-string-string',
        });

      expect(status).toBe(400);
      expect(body).toEqual(factory.responses.badRequest(['metadata must be valid JSON']));
    });

    it('should validate iCloudId is a string', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({
          ...makeUploadDto(),
          metadata: JSON.stringify([{ key: AssetMetadataKey.MobileApp, value: { iCloudId: 123 } }]),
        });

      expect(status).toBe(400);
      expect(body).toEqual(factory.responses.badRequest(['metadata.0.value.iCloudId must be a string']));
    });

    it('should require `deviceAssetId`', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({ ...makeUploadDto({ omit: 'deviceAssetId' }) });
      expect(status).toBe(400);
      expect(body).toEqual(
        factory.responses.badRequest(['deviceAssetId must be a string', 'deviceAssetId should not be empty']),
      );
    });

    it('should require `deviceId`', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({ ...makeUploadDto({ omit: 'deviceId' }) });
      expect(status).toBe(400);
      expect(body).toEqual(factory.responses.badRequest(['deviceId must be a string', 'deviceId should not be empty']));
    });

    it('should require `fileCreatedAt`', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({ ...makeUploadDto({ omit: 'fileCreatedAt' }) });
      expect(status).toBe(400);
      expect(body).toEqual(
        factory.responses.badRequest(['fileCreatedAt must be a Date instance', 'fileCreatedAt should not be empty']),
      );
    });

    it('should require `fileModifiedAt`', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field(makeUploadDto({ omit: 'fileModifiedAt' }));
      expect(status).toBe(400);
      expect(body).toEqual(
        factory.responses.badRequest(['fileModifiedAt must be a Date instance', 'fileModifiedAt should not be empty']),
      );
    });

    it('should throw if `isFavorite` is not a boolean', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({ ...makeUploadDto(), isFavorite: 'not-a-boolean' });
      expect(status).toBe(400);
      expect(body).toEqual(factory.responses.badRequest(['isFavorite must be a boolean value']));
    });

    it('should throw if `visibility` is not an enum', async () => {
      const { status, body } = await request(ctx.getHttpServer())
        .post('/assets')
        .attach('assetData', assetData, filename)
        .field({ ...makeUploadDto(), visibility: 'not-an-option' });
      expect(status).toBe(400);
      expect(body).toEqual(
        factory.responses.badRequest([expect.stringContaining('visibility must be one of the following values:')]),
      );
    });

    // TODO figure out how to deal with `sendFile`
    describe.skip('GET /assets/:id/original', () => {
      it('should be an authenticated route', async () => {
        await request(ctx.getHttpServer()).get(`/assets/${factory.uuid()}/original`);
        expect(ctx.authenticate).toHaveBeenCalled();
      });
    });

    // TODO figure out how to deal with `sendFile`
    describe.skip('GET /assets/:id/thumbnail', () => {
      it('should be an authenticated route', async () => {
        await request(ctx.getHttpServer()).get(`/assets/${factory.uuid()}/thumbnail`);
        expect(ctx.authenticate).toHaveBeenCalled();
      });
    });
  });

  describe('Resumable upload routes', () => {
    it('should create upload session', async () => {
      const body = {
        deviceAssetId: 'example-image',
        deviceId: 'WEB',
        fileCreatedAt: new Date().toISOString(),
        fileModifiedAt: new Date().toISOString(),
        isFavorite: false,
        duration: '0:00:00.000000',
        fileName: 'example.webm',
        fileSize: 10,
        chunkSize: 10,
        totalChunks: 1,
        checksum: 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3',
      };

      const { status } = await request(ctx.getHttpServer()).post('/assets/upload-sessions').send(body);
      expect(status).toBe(201);
      expect(uploadSessionService.create).toHaveBeenCalled();
    });

    it('should upload chunk', async () => {
      const sessionId = factory.uuid();
      const { status } = await request(ctx.getHttpServer())
        .put(`/assets/upload-sessions/${sessionId}/chunks/0`)
        .set('Content-Type', 'application/octet-stream')
        .send(Buffer.from('1234567890'));

      expect(status).toBe(200);
      expect(uploadSessionService.uploadChunk).toHaveBeenCalled();
    });
  });
});
