import { authManager } from '$lib/managers/auth-manager.svelte';
import { uploadManager } from '$lib/managers/upload-manager.svelte';
import { UploadState } from '$lib/models/upload-asset';
import { uploadAssetsStore } from '$lib/stores/upload';
import { user } from '$lib/stores/user.store';
import { uploadRequest } from '$lib/utils';
import { addAssetsToAlbum } from '$lib/utils/asset-utils';
import { ExecutorQueue } from '$lib/utils/executor-queue';
import { asQueryString } from '$lib/utils/shared-links';
import {
  Action,
  AssetMediaStatus,
  AssetVisibility,
  checkBulkUpload,
  getBaseUrl,
  type AssetMediaResponseDto,
} from '@immich/sdk';
import { createSHA1 } from 'hash-wasm'; // pizcloud
// import { getBaseUrl } from '$lib/pizcloud'; // pizcloud

import { tick } from 'svelte';
import { t } from 'svelte-i18n';
import { get } from 'svelte/store';
import { getUploadErrorMessage, handleError } from './handle-error'; // pizcloud

export const addDummyItems = () => {
  uploadAssetsStore.addItem({ id: 'asset-0', file: { name: 'asset0.jpg', size: 123_456 } as File });
  uploadAssetsStore.updateItem('asset-0', { state: UploadState.PENDING });
  uploadAssetsStore.addItem({ id: 'asset-1', file: { name: 'asset1.jpg', size: 123_456 } as File });
  uploadAssetsStore.updateItem('asset-1', { state: UploadState.STARTED });
  uploadAssetsStore.updateProgress('asset-1', 75, 100);
  uploadAssetsStore.addItem({ id: 'asset-2', file: { name: 'asset2.jpg', size: 123_456 } as File });
  uploadAssetsStore.updateItem('asset-2', { state: UploadState.ERROR, error: new Error('Internal server error') });
  uploadAssetsStore.addItem({ id: 'asset-3', file: { name: 'asset3.jpg', size: 123_456 } as File });
  uploadAssetsStore.updateItem('asset-3', { state: UploadState.DUPLICATED, assetId: 'asset-2' });
  uploadAssetsStore.addItem({ id: 'asset-4', file: { name: 'asset3.jpg', size: 123_456 } as File });
  uploadAssetsStore.updateItem('asset-4', { state: UploadState.DUPLICATED, assetId: 'asset-2', isTrashed: true });
  uploadAssetsStore.addItem({ id: 'asset-10', file: { name: 'asset3.jpg', size: 123_456 } as File });
  uploadAssetsStore.updateItem('asset-10', { state: UploadState.DONE });
  uploadAssetsStore.track('error');
  uploadAssetsStore.track('success');
  uploadAssetsStore.track('duplicate');
};

// addDummyItems();

export const uploadExecutionQueue = new ExecutorQueue({ concurrency: 2 });
// pizcloud
const HASH_CHUNK_SIZE = 8 * 1024 * 1024; // 8 MiB
const HASH_YIELD_INTERVAL_CHUNKS = 16;
const RESUMABLE_UPLOAD_CHUNK_SIZE = 8 * 1024 * 1024; // 8 MiB
const RESUMABLE_UPLOAD_MIN_FILE_SIZE = 128 * 1024 * 1024; // 128 MiB
const RESUMABLE_SESSION_STORAGE_KEY = 'pizcloud-resumable-upload-sessions-v1';

async function calculateSha1Checksum(file: Blob): Promise<string> {
  const sha1 = await createSHA1();
  sha1.init();

  for (let offset = 0, chunkIndex = 0; offset < file.size; offset += HASH_CHUNK_SIZE, chunkIndex++) {
    const chunk = file.slice(offset, offset + HASH_CHUNK_SIZE);
    const bytes = await chunk.arrayBuffer();
    sha1.update(new Uint8Array(bytes));

    // Yield periodically so large file hashing does not monopolize the UI thread.
    if ((chunkIndex + 1) % HASH_YIELD_INTERVAL_CHUNKS === 0) {
      await Promise.resolve();
    }
  }

  return sha1.digest('hex');
}

class HttpRequestError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly details?: unknown,
  ) {
    super(message);
  }
}

type UploadSessionCreateResponseDto = {
  status: 'active' | 'duplicate';
  id?: string;
  assetId?: string;
  isTrashed?: boolean;
  chunkSize?: number;
  totalChunks?: number;
  uploadedChunks?: number[];
};

type UploadSessionStatusResponseDto = {
  status: 'active' | 'completed';
  id: string;
  chunkSize: number;
  totalChunks: number;
  fileSize: number;
  uploadedChunks: number[];
};

type UploadSessionChunkResponseDto = {
  id: string;
  chunkIndex: number;
  uploadedChunks: number[];
};

type UploadSessionActive = {
  id: string;
  chunkSize: number;
  totalChunks: number;
  uploadedChunks: number[];
};

type ResumableSessionCacheEntry = {
  sessionId: string;
  deviceAssetId: string;
  fileName: string;
  fileSize: number;
  lastModified: number;
  albumId?: string;
  isLockedAssets?: boolean;
  updatedAt: number;
};

type ResumableSessionCacheValue = string | ResumableSessionCacheEntry;
type ResumableSessionCache = Record<string, ResumableSessionCacheValue>;

export type InterruptedUploadSessionEntry = ResumableSessionCacheEntry & { cacheKey: string };
export type InterruptedUploadSessionStatus = UploadSessionStatusResponseDto;
// #pizcloud

type FileUploadParam = { multiple?: boolean; albumId?: string };

export const openFileUploadDialog = async (options: FileUploadParam = {}) => {
  const { albumId, multiple = true } = options;
  const extensions = uploadManager.getExtensions();

  return new Promise<string[]>((resolve, reject) => {
    try {
      const fileSelector = document.createElement('input');

      fileSelector.type = 'file';
      fileSelector.multiple = multiple;
      fileSelector.accept = extensions.join(',');
      fileSelector.addEventListener(
        'change',
        (e: Event) => {
          const target = e.target as HTMLInputElement;
          if (!target.files) {
            return;
          }
          const files = Array.from(target.files);

          resolve(fileUploadHandler({ files, albumId }));
        },
        { passive: true },
      );

      fileSelector.click();
    } catch (error) {
      console.log('Error selecting file', error);
      reject(error);
    }
  });
};

type FileUploadHandlerParams = Omit<FileUploaderParams, 'deviceAssetId' | 'assetFile'> & {
  files: File[];
};

export const fileUploadHandler = async ({
  files,
  albumId,
  isLockedAssets = false,
}: FileUploadHandlerParams): Promise<string[]> => {
  const extensions = uploadManager.getExtensions();
  const promises = [];
  for (const file of files) {
    const name = file.name.toLowerCase();
    if (extensions.some((extension) => name.endsWith(extension))) {
      const deviceAssetId = getDeviceAssetId(file);
      uploadAssetsStore.addItem({ id: deviceAssetId, file, albumId });
      promises.push(
        uploadExecutionQueue.addTask(() => fileUploader({ assetFile: file, deviceAssetId, albumId, isLockedAssets })),
      );
    }
  }

  const results = await Promise.all(promises);
  return results.filter((result): result is string => !!result);
};

function getDeviceAssetId(asset: File) {
  return 'web' + '-' + asset.name + '-' + asset.lastModified;
}

// pizcloud
function shouldUseResumableUpload(asset: File) {
  return asset.size >= RESUMABLE_UPLOAD_MIN_FILE_SIZE;
}

function getResumableUploadCacheKey(asset: File, deviceAssetId: string) {
  return `${deviceAssetId}:${asset.size}:${asset.lastModified}`;
}

function readResumableSessionCache(): ResumableSessionCache {
  try {
    const value = globalThis.localStorage?.getItem(RESUMABLE_SESSION_STORAGE_KEY);
    if (!value) {
      return {};
    }
    const parsed = JSON.parse(value) as unknown;
    return typeof parsed === 'object' && parsed ? (parsed as ResumableSessionCache) : {};
  } catch {
    return {};
  }
}

function writeResumableSessionCache(cache: ResumableSessionCache) {
  try {
    globalThis.localStorage?.setItem(RESUMABLE_SESSION_STORAGE_KEY, JSON.stringify(cache));
  } catch {
    // Ignore storage failures; resumable still works within the current runtime.
  }
}

function setResumableSessionEntry(cacheKey: string, entry: ResumableSessionCacheEntry) {
  const cache = readResumableSessionCache();
  cache[cacheKey] = entry;
  writeResumableSessionCache(cache);
}

function getResumableSessionId(cacheKey: string): string | undefined {
  const value = readResumableSessionCache()[cacheKey];
  return typeof value === 'string' ? value : value?.sessionId;
}

function removeResumableSessionCacheEntry(cacheKey: string) {
  const cache = readResumableSessionCache();
  if (!(cacheKey in cache)) {
    return;
  }
  delete cache[cacheKey];
  writeResumableSessionCache(cache);
}

async function requestJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    credentials: 'include',
  });

  const text = await response.text();
  let body: unknown = {};
  if (text) {
    try {
      body = JSON.parse(text) as unknown;
    } catch {
      body = { message: text };
    }
  }
  if (!response.ok) {
    const message =
      typeof body === 'object' && body && 'message' in body && typeof body.message === 'string'
        ? body.message
        : response.statusText || 'Request failed';
    throw new HttpRequestError(message, response.status, body);
  }

  return body as T;
}

function setResumableSessionFromFile({
  cacheKey,
  sessionId,
  file,
  deviceAssetId,
  albumId,
  isLockedAssets,
}: {
  cacheKey: string;
  sessionId: string;
  file: File;
  deviceAssetId: string;
  albumId?: string;
  isLockedAssets?: boolean;
}) {
  setResumableSessionEntry(cacheKey, {
    sessionId,
    deviceAssetId,
    fileName: file.name,
    fileSize: file.size,
    lastModified: file.lastModified,
    albumId,
    isLockedAssets,
    updatedAt: Date.now(),
  });
}

export function listInterruptedUploadSessionEntries(): InterruptedUploadSessionEntry[] {
  const cache = readResumableSessionCache();
  const entries: InterruptedUploadSessionEntry[] = [];

  for (const [cacheKey, value] of Object.entries(cache)) {
    if (typeof value === 'string') {
      continue;
    }
    entries.push({ cacheKey, ...value });
  }

  // Legacy (kept for reference): `return entries.toSorted((a, b) => b.updatedAt - a.updatedAt);`
  return entries.slice().sort((a, b) => b.updatedAt - a.updatedAt);
}

export function removeInterruptedUploadSessionEntry(cacheKey: string) {
  removeResumableSessionCacheEntry(cacheKey);
}

export async function getInterruptedUploadSessionStatus(sessionId: string): Promise<InterruptedUploadSessionStatus> {
  const queryParams = asQueryString(authManager.params);
  const statusUrl = `${getBaseUrl()}/assets/upload-sessions/${sessionId}${queryParams ? `?${queryParams}` : ''}`;
  return await requestJson<UploadSessionStatusResponseDto>(statusUrl, { method: 'GET' });
}

export async function cancelInterruptedUploadSession(sessionId: string): Promise<void> {
  const queryParams = asQueryString(authManager.params);
  const cancelUrl = `${getBaseUrl()}/assets/upload-sessions/${sessionId}${queryParams ? `?${queryParams}` : ''}`;
  try {
    await requestJson<unknown>(cancelUrl, { method: 'DELETE' });
  } catch (error) {
    const status = (error as { status?: number } | undefined)?.status;
    if (status !== 404) {
      throw error;
    }
  }
}

export async function resumeInterruptedUploadSession({
  entry,
  file,
}: {
  entry: InterruptedUploadSessionEntry;
  file: File;
}): Promise<string[]> {
  if (file.name !== entry.fileName || file.size !== entry.fileSize || file.lastModified !== entry.lastModified) {
    throw new Error('Selected file does not match interrupted upload');
  }

  setResumableSessionFromFile({
    cacheKey: entry.cacheKey,
    sessionId: entry.sessionId,
    file,
    deviceAssetId: entry.deviceAssetId,
    albumId: entry.albumId,
    isLockedAssets: entry.isLockedAssets,
  });

  return await fileUploadHandler({
    files: [file],
    albumId: entry.albumId,
    isLockedAssets: entry.isLockedAssets ?? false,
  });
}
// #pizcloud

type FileUploaderParams = {
  assetFile: File;
  albumId?: string;
  replaceAssetId?: string;
  isLockedAssets?: boolean;
  deviceAssetId: string;
};

// pizcloud
async function createOrResumeUploadSession({
  assetFile,
  checksum,
  deviceAssetId,
  isLockedAssets,
  albumId,
}: {
  assetFile: File;
  checksum: string;
  deviceAssetId: string;
  isLockedAssets: boolean;
  albumId?: string;
}): Promise<
  | { type: 'duplicate'; data: { id: string; status: AssetMediaStatus.Duplicate; isTrashed?: boolean } }
  | { type: 'active'; session: UploadSessionActive; cacheKey: string }
> {
  const queryParams = asQueryString(authManager.params);
  const baseUrl = getBaseUrl();
  const cacheKey = getResumableUploadCacheKey(assetFile, deviceAssetId);
  const cachedSessionId = getResumableSessionId(cacheKey);
  const statusUrl = (sessionId: string) =>
    `${baseUrl}/assets/upload-sessions/${sessionId}${queryParams ? `?${queryParams}` : ''}`;

  if (cachedSessionId) {
    try {
      const session = await requestJson<UploadSessionStatusResponseDto>(statusUrl(cachedSessionId), { method: 'GET' });
      setResumableSessionFromFile({
        cacheKey,
        sessionId: session.id,
        file: assetFile,
        deviceAssetId,
        albumId,
        isLockedAssets,
      });
      return {
        type: 'active',
        cacheKey,
        session: {
          id: session.id,
          chunkSize: session.chunkSize,
          totalChunks: session.totalChunks,
          uploadedChunks: session.uploadedChunks,
        },
      };
    } catch {
      removeResumableSessionCacheEntry(cacheKey);
    }
  }

  const totalChunks = Math.ceil(assetFile.size / RESUMABLE_UPLOAD_CHUNK_SIZE);
  const payload = {
    deviceAssetId,
    deviceId: 'WEB',
    fileCreatedAt: new Date(assetFile.lastModified).toISOString(),
    fileModifiedAt: new Date(assetFile.lastModified).toISOString(),
    isFavorite: false,
    duration: '0:00:00.000000',
    visibility: isLockedAssets ? AssetVisibility.Locked : undefined,
    fileName: assetFile.name,
    fileSize: assetFile.size,
    chunkSize: RESUMABLE_UPLOAD_CHUNK_SIZE,
    totalChunks,
    checksum,
  };

  const createUrl = `${baseUrl}/assets/upload-sessions${queryParams ? `?${queryParams}` : ''}`;
  const session = await requestJson<UploadSessionCreateResponseDto>(createUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });

  if (session.status === 'duplicate' && session.assetId) {
    removeResumableSessionCacheEntry(cacheKey);
    return {
      type: 'duplicate',
      data: {
        id: session.assetId,
        status: AssetMediaStatus.Duplicate,
        isTrashed: session.isTrashed,
      },
    };
  }

  if (!session.id || !session.chunkSize || !session.totalChunks || !session.uploadedChunks) {
    throw new Error('Invalid upload session response');
  }

  setResumableSessionFromFile({
    cacheKey,
    sessionId: session.id,
    file: assetFile,
    deviceAssetId,
    albumId,
    isLockedAssets,
  });
  return {
    type: 'active',
    cacheKey,
    session: {
      id: session.id,
      chunkSize: session.chunkSize,
      totalChunks: session.totalChunks,
      uploadedChunks: session.uploadedChunks,
    },
  };
}

async function uploadAssetResumable({
  assetFile,
  checksum,
  deviceAssetId,
  isLockedAssets,
  albumId,
}: {
  assetFile: File;
  checksum: string;
  deviceAssetId: string;
  isLockedAssets: boolean;
  albumId?: string;
}): Promise<{ id: string; status: AssetMediaStatus; isTrashed?: boolean }> {
  const sessionResult = await createOrResumeUploadSession({
    assetFile,
    checksum,
    deviceAssetId,
    isLockedAssets,
    albumId,
  });
  if (sessionResult.type === 'duplicate') {
    return sessionResult.data;
  }

  const { session, cacheKey } = sessionResult;
  const queryParams = asQueryString(authManager.params);
  const baseUrl = getBaseUrl();
  const uploadedChunks = new Set(session.uploadedChunks);

  const updateProgress = () => {
    const uploadedBytes = Math.min(assetFile.size, uploadedChunks.size * session.chunkSize);
    uploadAssetsStore.updateProgress(deviceAssetId, uploadedBytes, assetFile.size);
  };

  updateProgress();

  for (let chunkIndex = 0; chunkIndex < session.totalChunks; chunkIndex++) {
    if (uploadedChunks.has(chunkIndex)) {
      continue;
    }

    const offset = chunkIndex * session.chunkSize;
    const chunk = assetFile.slice(offset, offset + session.chunkSize);
    const chunkUrl = `${baseUrl}/assets/upload-sessions/${session.id}/chunks/${chunkIndex}${queryParams ? `?${queryParams}` : ''}`;

    const chunkResponse = await requestJson<UploadSessionChunkResponseDto>(chunkUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/octet-stream' },
      body: chunk,
    });
    uploadedChunks.clear();
    for (const uploadedChunk of chunkResponse.uploadedChunks) {
      uploadedChunks.add(uploadedChunk);
    }
    updateProgress();
  }

  const completeUrl = `${baseUrl}/assets/upload-sessions/${session.id}/complete${queryParams ? `?${queryParams}` : ''}`;
  const response = await requestJson<AssetMediaResponseDto>(completeUrl, { method: 'POST' });
  removeResumableSessionCacheEntry(cacheKey);
  return response;
}
// #pizcloud

// TODO: should probably use the @api SDK
async function fileUploader({
  assetFile,
  deviceAssetId,
  albumId,
  isLockedAssets = false,
}: FileUploaderParams): Promise<string | undefined> {
  const fileCreatedAt = new Date(assetFile.lastModified).toISOString();
  const $t = get(t);

  uploadAssetsStore.markStarted(deviceAssetId);

  try {
    const formData = new FormData();
    for (const [key, value] of Object.entries({
      deviceAssetId,
      deviceId: 'WEB',
      fileCreatedAt,
      fileModifiedAt: new Date(assetFile.lastModified).toISOString(),
      isFavorite: 'false',
      duration: '0:00:00.000000',
      assetData: new File([assetFile], assetFile.name),
    })) {
      formData.append(key, value);
    }

    if (isLockedAssets) {
      formData.append('visibility', AssetVisibility.Locked);
    }

    let calculatedChecksum: string | undefined; // #pizcloud
    let responseData: { id: string; status: AssetMediaStatus; isTrashed?: boolean } | undefined;
    // pizcloud - Legacy gate (kept for reference): `crypto?.subtle?.digest && !authManager.isSharedLink`
    if (!authManager.isSharedLink) {
      uploadAssetsStore.updateItem(deviceAssetId, { message: $t('asset_hashing') });
      await tick();
      try {
        // pizcloud
        // const bytes = await assetFile.arrayBuffer();
        // const hash = await crypto.subtle.digest('SHA-1', bytes);
        // const checksum = Array.from(new Uint8Array(hash))
        //   .map((b) => b.toString(16).padStart(2, '0'))
        //   .join('');

        calculatedChecksum = await calculateSha1Checksum(assetFile);
        // #pizcloud

        const {
          results: [checkUploadResult],
        } = await checkBulkUpload({
          assetBulkUploadCheckDto: { assets: [{ id: assetFile.name, checksum: calculatedChecksum }] },
        });
        if (checkUploadResult.action === Action.Reject && checkUploadResult.assetId) {
          responseData = {
            status: AssetMediaStatus.Duplicate,
            id: checkUploadResult.assetId,
            isTrashed: checkUploadResult.isTrashed,
          };
        }
      } catch (error) {
        console.error(`Error calculating sha1 file=${assetFile.name})`, error);
      }
    }

    if (!responseData) {
      uploadAssetsStore.updateItem(deviceAssetId, { message: $t('asset_uploading') });

      // pizcloud
      if (shouldUseResumableUpload(assetFile)) {
        try {
          const checksum = calculatedChecksum ?? (await calculateSha1Checksum(assetFile));
          responseData = await uploadAssetResumable({
            assetFile,
            checksum,
            deviceAssetId,
            isLockedAssets,
            albumId,
          });
        } catch (error) {
          if (!(error instanceof HttpRequestError) || ![404, 405, 501].includes(error.status)) {
            throw error;
          }
          console.warn('Resumable upload endpoint unavailable, fallback to multipart upload');
        }
      }

      if (!responseData) {
        const queryParams = asQueryString(authManager.params);
        const response = await uploadRequest<AssetMediaResponseDto>({
          url: getBaseUrl() + '/assets' + (queryParams ? `?${queryParams}` : ''),
          data: formData,
          onUploadProgress: (event) => uploadAssetsStore.updateProgress(deviceAssetId, event.loaded, event.total),
        });

        if (![200, 201].includes(response.status)) {
          throw new Error($t('errors.unable_to_upload_file'));
        }

        responseData = response.data;
      }
      // #pizcloud
    }

    if (responseData.status === AssetMediaStatus.Duplicate) {
      uploadAssetsStore.track('duplicate');
    } else {
      uploadAssetsStore.track('success');
    }

    if (albumId) {
      uploadAssetsStore.updateItem(deviceAssetId, { message: $t('asset_adding_to_album') });
      await addAssetsToAlbum(albumId, [responseData.id], false);
      uploadAssetsStore.updateItem(deviceAssetId, { message: $t('asset_added_to_album') });
    }

    uploadAssetsStore.updateItem(deviceAssetId, {
      state: responseData.status === AssetMediaStatus.Duplicate ? UploadState.DUPLICATED : UploadState.DONE,
      assetId: responseData.id,
      isTrashed: responseData.isTrashed,
    });

    if (responseData.status !== AssetMediaStatus.Duplicate) {
      setTimeout(() => {
        uploadAssetsStore.removeItem(deviceAssetId);
      }, 1000);
    }

    return responseData.id;
  } catch (error) {
    // ignore errors if the user logs out during uploads
    if (!get(user)) {
      return;
    }

    // pizcloud
    const uploadError = getUploadErrorMessage(error, {
      fallback: $t('errors.unable_to_upload_file'),
      demoAccountReadOnly: $t('errors.upload_error_demo_account_read_only'),
      forbidden: $t('errors.upload_error_forbidden'),
    });

    // const errorMessage = handleError(error, $t('errors.unable_to_upload_file'));
    const errorMessage = handleError(error, uploadError.message, {
      preferServerMessage: uploadError.preferServerMessage,
    });
    // #pizcloud
    uploadAssetsStore.track('error');
    uploadAssetsStore.updateItem(deviceAssetId, { state: UploadState.ERROR, error: errorMessage });
    return;
  }
}
