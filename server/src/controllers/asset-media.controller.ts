import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Next,
  Param,
  ParseFilePipe,
  ParseIntPipe,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
  Req,
  Res,
  UploadedFiles,
  UseInterceptors,
} from '@nestjs/common';
import { ApiBody, ApiConsumes, ApiHeader, ApiTags } from '@nestjs/swagger';
import { NextFunction, Request, Response } from 'express';
import { Endpoint, HistoryBuilder } from 'src/decorators';
import {
  AssetBulkUploadCheckResponseDto,
  AssetMediaResponseDto,
  AssetMediaStatus,
  AssetUploadSessionChunkResponseDto,
  AssetUploadSessionCreateResponseDto,
  AssetUploadSessionDeleteResponseDto,
  AssetUploadSessionStatus,
  AssetUploadSessionStatusResponseDto,
  CheckExistingAssetsResponseDto,
} from 'src/dtos/asset-media-response.dto';
import {
  AssetBulkUploadCheckDto,
  AssetMediaCreateDto,
  AssetMediaOptionsDto,
  AssetMediaReplaceDto,
  AssetMediaSize,
  AssetUploadSessionCreateDto,
  CheckExistingAssetsDto,
  UploadFieldName,
} from 'src/dtos/asset-media.dto';
import { AuthDto } from 'src/dtos/auth.dto';
import { ApiTag, ImmichHeader, Permission, RouteKey } from 'src/enum';
import { AssetUploadInterceptor } from 'src/middleware/asset-upload.interceptor';
import { Auth, Authenticated, FileResponse } from 'src/middleware/auth.guard';
import { FileUploadInterceptor, getFiles } from 'src/middleware/file-upload.interceptor';
import { LoggingRepository } from 'src/repositories/logging.repository';
import { AssetMediaService } from 'src/services/asset-media.service';
import { AssetUploadSessionService } from 'src/services/asset-upload-session.service'; // pizcloud
import { UploadFiles } from 'src/types';
import { ImmichFileResponse, sendFile } from 'src/utils/file';
import { FileNotEmptyValidator, UUIDParamDto } from 'src/validation';

@ApiTags(ApiTag.Assets)
@Controller(RouteKey.Asset)
export class AssetMediaController {
  constructor(
    private logger: LoggingRepository,
    private service: AssetMediaService,
    private uploadSessionService: AssetUploadSessionService,
  ) { }

  @Post()
  @Authenticated({ permission: Permission.AssetUpload, sharedLink: true })
  @UseInterceptors(AssetUploadInterceptor, FileUploadInterceptor)
  @ApiConsumes('multipart/form-data')
  @ApiHeader({
    name: ImmichHeader.Checksum,
    description: 'sha1 checksum that can be used for duplicate detection before the file is uploaded',
    required: false,
  })
  @ApiBody({ description: 'Asset Upload Information', type: AssetMediaCreateDto })
  @Endpoint({
    summary: 'Upload asset',
    description: 'Uploads a new asset to the server.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  async uploadAsset(
    @Auth() auth: AuthDto,
    @UploadedFiles(new ParseFilePipe({ validators: [new FileNotEmptyValidator(['assetData'])] })) files: UploadFiles,
    @Body() dto: AssetMediaCreateDto,
    @Res({ passthrough: true }) res: Response,
  ): Promise<AssetMediaResponseDto> {
    const { file, sidecarFile } = getFiles(files);
    const responseDto = await this.service.uploadAsset(auth, dto, file, sidecarFile);

    if (responseDto.status === AssetMediaStatus.DUPLICATE) {
      res.status(HttpStatus.OK);
    }

    return responseDto;
  }

  // pizcloud
  @Post('upload-sessions')
  @Authenticated({ permission: Permission.AssetUpload, sharedLink: true })
  @Endpoint({
    summary: 'Create upload session',
    description: 'Create a resumable upload session for chunked file uploads.',
    history: new HistoryBuilder().added('v1'),
  })
  async createUploadSession(
    @Auth() auth: AuthDto,
    @Body() dto: AssetUploadSessionCreateDto,
    @Res({ passthrough: true }) res: Response,
  ): Promise<AssetUploadSessionCreateResponseDto> {
    const responseDto = await this.uploadSessionService.create(auth, dto);
    if (responseDto.status === AssetUploadSessionStatus.DUPLICATE) {
      res.status(HttpStatus.OK);
    }

    return responseDto;
  }

  @Get('upload-sessions/:id')
  @Authenticated({ permission: Permission.AssetUpload, sharedLink: true })
  @Endpoint({
    summary: 'Get upload session',
    description: 'Get the upload progress for a resumable upload session.',
    history: new HistoryBuilder().added('v1'),
  })
  async getUploadSession(
    @Auth() auth: AuthDto,
    @Param('id', new ParseUUIDPipe()) id: string,
  ): Promise<AssetUploadSessionStatusResponseDto> {
    return await this.uploadSessionService.getStatus(auth, id);
  }

  @Put('upload-sessions/:id/chunks/:chunkIndex')
  @Authenticated({ permission: Permission.AssetUpload, sharedLink: true })
  @ApiConsumes('application/octet-stream')
  @Endpoint({
    summary: 'Upload chunk',
    description: 'Upload a single chunk for a resumable upload session.',
    history: new HistoryBuilder().added('v1'),
  })
  @HttpCode(HttpStatus.OK)
  async uploadAssetChunk(
    @Auth() auth: AuthDto,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Param('chunkIndex', ParseIntPipe) chunkIndex: number,
    @Req() req: Request,
  ): Promise<AssetUploadSessionChunkResponseDto> {
    return await this.uploadSessionService.uploadChunk(auth, id, chunkIndex, req);
  }

  @Post('upload-sessions/:id/complete')
  @Authenticated({ permission: Permission.AssetUpload, sharedLink: true })
  @Endpoint({
    summary: 'Complete upload session',
    description: 'Complete a resumable upload session and create the final asset.',
    history: new HistoryBuilder().added('v1'),
  })
  async completeUploadSession(
    @Auth() auth: AuthDto,
    @Param('id', new ParseUUIDPipe()) id: string,
  ): Promise<AssetMediaResponseDto> {
    return await this.uploadSessionService.complete(auth, id);
  }

  @Delete('upload-sessions/:id')
  @Authenticated({ permission: Permission.AssetUpload, sharedLink: true })
  @Endpoint({
    summary: 'Delete upload session',
    description: 'Cancel and delete a resumable upload session.',
    history: new HistoryBuilder().added('v1'),
  })
  async deleteUploadSession(
    @Auth() auth: AuthDto,
    @Param('id', new ParseUUIDPipe()) id: string,
  ): Promise<AssetUploadSessionDeleteResponseDto> {
    return await this.uploadSessionService.delete(auth, id);
  }
  // #pizcloud

  @Get(':id/original')
  @FileResponse()
  @Authenticated({ permission: Permission.AssetDownload, sharedLink: true })
  @Endpoint({
    summary: 'Download original asset',
    description: 'Downloads the original file of the specified asset.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  async downloadAsset(
    @Auth() auth: AuthDto,
    @Param() { id }: UUIDParamDto,
    @Res() res: Response,
    @Next() next: NextFunction,
    @Query('download') download?: string, // pizcloud
  ) {
    const isDownload = download === '1' || download === 'true'; // pizcloud
    await sendFile(res, next, () => this.service.downloadOriginal(auth, id, isDownload), this.logger); // pizcloud
  }

  @Put(':id/original')
  @UseInterceptors(FileUploadInterceptor)
  @ApiConsumes('multipart/form-data')
  @Endpoint({
    summary: 'Replace asset',
    description: 'Replace the asset with new file, without changing its id.',
    history: new HistoryBuilder().added('v1').deprecated('v1', { replacementId: 'copyAsset' }),
  })
  @Authenticated({ permission: Permission.AssetReplace, sharedLink: true })
  async replaceAsset(
    @Auth() auth: AuthDto,
    @Param() { id }: UUIDParamDto,
    @UploadedFiles(new ParseFilePipe({ validators: [new FileNotEmptyValidator([UploadFieldName.ASSET_DATA])] }))
    files: UploadFiles,
    @Body() dto: AssetMediaReplaceDto,
    @Res({ passthrough: true }) res: Response,
  ): Promise<AssetMediaResponseDto> {
    const { file } = getFiles(files);
    const responseDto = await this.service.replaceAsset(auth, id, dto, file);
    if (responseDto.status === AssetMediaStatus.DUPLICATE) {
      res.status(HttpStatus.OK);
    }
    return responseDto;
  }

  @Get(':id/thumbnail')
  @FileResponse()
  @Authenticated({ permission: Permission.AssetView, sharedLink: true })
  @Endpoint({
    summary: 'View asset thumbnail',
    description: 'Retrieve the thumbnail image for the specified asset.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  async viewAsset(
    @Auth() auth: AuthDto,
    @Param() { id }: UUIDParamDto,
    @Query() dto: AssetMediaOptionsDto,
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    const viewThumbnailRes = await this.service.viewThumbnail(auth, id, dto);

    if (viewThumbnailRes instanceof ImmichFileResponse) {
      await sendFile(res, next, () => Promise.resolve(viewThumbnailRes), this.logger);
    } else {
      // viewThumbnailRes is a AssetMediaRedirectResponse
      // which redirects to the original asset or a specific size to make better use of caching
      const { targetSize } = viewThumbnailRes;
      const [reqPath, reqSearch] = req.url.split('?');
      let redirPath: string;
      const redirSearchParams = new URLSearchParams(reqSearch);
      if (targetSize === 'original') {
        // relative path to this.downloadAsset
        redirPath = 'original';
        redirSearchParams.delete('size');
      } else if (Object.values(AssetMediaSize).includes(targetSize)) {
        redirPath = reqPath;
        redirSearchParams.set('size', targetSize);
      } else {
        throw new Error('Invalid targetSize: ' + targetSize);
      }
      const finalRedirPath = redirPath + '?' + redirSearchParams.toString();
      return res.redirect(finalRedirPath);
    }
  }

  @Get(':id/video/playback')
  @FileResponse()
  @Authenticated({ permission: Permission.AssetView, sharedLink: true })
  @Endpoint({
    summary: 'Play asset video',
    description: 'Streams the video file for the specified asset. This endpoint also supports byte range requests.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  async playAssetVideo(
    @Auth() auth: AuthDto,
    @Param() { id }: UUIDParamDto,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    await sendFile(res, next, () => this.service.playbackVideo(auth, id), this.logger);
  }

  @Post('exist')
  @Authenticated()
  @Endpoint({
    summary: 'Check existing assets',
    description: 'Checks if multiple assets exist on the server and returns all existing - used by background backup',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  @HttpCode(HttpStatus.OK)
  checkExistingAssets(
    @Auth() auth: AuthDto,
    @Body() dto: CheckExistingAssetsDto,
  ): Promise<CheckExistingAssetsResponseDto> {
    return this.service.checkExistingAssets(auth, dto);
  }

  @Post('bulk-upload-check')
  @Authenticated({ permission: Permission.AssetUpload })
  @Endpoint({
    summary: 'Check bulk upload',
    description: 'Determine which assets have already been uploaded to the server based on their SHA1 checksums.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  @HttpCode(HttpStatus.OK)
  checkBulkUpload(
    @Auth() auth: AuthDto,
    @Body() dto: AssetBulkUploadCheckDto,
  ): Promise<AssetBulkUploadCheckResponseDto> {
    return this.service.bulkUploadCheck(auth, dto);
  }
}
