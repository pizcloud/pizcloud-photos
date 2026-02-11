import { getApiBaseUrl } from '$lib/utils/api-base';

export type AlbumTransferUser = {
  id: string;
  name: string;
  email: string;
};

export enum AlbumTransferStatus {
  Pending = 'pending',
  Accepted = 'accepted',
  Declined = 'declined',
  Canceled = 'canceled',
}

export type AlbumTransferDto = {
  id: string;
  albumId: string;
  albumName: string;
  fromUser: AlbumTransferUser;
  toUser: AlbumTransferUser;
  status: AlbumTransferStatus;
  createdAt: string;
  updatedAt: string;
  respondedAt: string | null;
  assetCount: number;
  totalBytes: number;
};

export class AlbumTransferApiError extends Error {
  status: number;
  code?: string;

  constructor(message: string, status: number, code?: string) {
    super(message);
    this.name = 'AlbumTransferApiError';
    this.status = status;
    this.code = code;
  }
}

type RequestOptions = {
  method: 'GET' | 'POST';
  body?: unknown;
};

const isObject = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null;
};

const normalizeUser = (value: unknown): AlbumTransferUser => {
  if (!isObject(value)) {
    return { id: '', name: '', email: '' };
  }

  return {
    id: typeof value.id === 'string' ? value.id : '',
    name: typeof value.name === 'string' ? value.name : '',
    email: typeof value.email === 'string' ? value.email : '',
  };
};

const normalizeStatus = (value: unknown): AlbumTransferStatus => {
  switch (value) {
    case AlbumTransferStatus.Pending:
      return AlbumTransferStatus.Pending;
    case AlbumTransferStatus.Accepted:
      return AlbumTransferStatus.Accepted;
    case AlbumTransferStatus.Declined:
      return AlbumTransferStatus.Declined;
    case AlbumTransferStatus.Canceled:
      return AlbumTransferStatus.Canceled;
    default:
      return AlbumTransferStatus.Pending;
  }
};

const normalizeTransfer = (value: unknown): AlbumTransferDto => {
  if (!isObject(value)) {
    throw new Error('Invalid transfer payload');
  }

  return {
    id: typeof value.id === 'string' ? value.id : '',
    albumId: typeof value.albumId === 'string' ? value.albumId : '',
    albumName: typeof value.albumName === 'string' ? value.albumName : '',
    fromUser: normalizeUser(value.fromUser),
    toUser: normalizeUser(value.toUser),
    status: normalizeStatus(value.status),
    createdAt: typeof value.createdAt === 'string' ? value.createdAt : '',
    updatedAt: typeof value.updatedAt === 'string' ? value.updatedAt : '',
    respondedAt: typeof value.respondedAt === 'string' ? value.respondedAt : null,
    assetCount: typeof value.assetCount === 'number' ? value.assetCount : 0,
    totalBytes: typeof value.totalBytes === 'number' ? value.totalBytes : 0,
  };
};

const parseErrorBody = async (res: Response): Promise<{ message: string; code?: string }> => {
  const text = await res.text();

  if (!text) {
    return { message: `Request failed (${res.status})` };
  }

  try {
    const parsed = JSON.parse(text) as unknown;
    if (isObject(parsed)) {
      const message = typeof parsed.message === 'string' ? parsed.message : text;
      return { message, code: typeof parsed.message === 'string' ? parsed.message : undefined };
    }
  } catch {

  }

  return { message: text };
};

const request = async (path: string, options: RequestOptions): Promise<Response> => {
  const baseUrl = getApiBaseUrl();

  return fetch(`${baseUrl}${path}`, {
    method: options.method,
    credentials: 'include',
    headers: {
      accept: 'application/json',
      ...(options.body ? { 'content-type': 'application/json' } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
};

const requestJson = async <T>(path: string, options: RequestOptions): Promise<T> => {
  const res = await request(path, options);

  if (!res.ok) {
    const parsed = await parseErrorBody(res);
    throw new AlbumTransferApiError(parsed.message, res.status, parsed.code);
  }

  return (await res.json()) as T;
};

export const getIncomingAlbumTransfers = async (): Promise<AlbumTransferDto[]> => {
  const data = await requestJson<unknown[]>('/album-transfers/incoming', { method: 'GET' });
  return Array.isArray(data) ? data.map((item) => normalizeTransfer(item)) : [];
};

export const getAlbumTransfer = async (albumId: string): Promise<AlbumTransferDto | null> => {
  const res = await request(`/albums/${albumId}/transfer`, { method: 'GET' });

  if (res.status === 404) {
    return null;
  }

  if (!res.ok) {
    const parsed = await parseErrorBody(res);
    throw new AlbumTransferApiError(parsed.message, res.status, parsed.code);
  }

  const text = await res.text();
  if (!text || text.trim() === 'null') {
    return null;
  }

  try {
    return normalizeTransfer(JSON.parse(text) as unknown);
  } catch {
    return null;
  }
};

export const requestAlbumTransfer = async (albumId: string, toUserId: string): Promise<AlbumTransferDto> => {
  const data = await requestJson<unknown>(`/albums/${albumId}/transfer`, {
    method: 'POST',
    body: { toUserId },
  });

  return normalizeTransfer(data);
};

export const cancelAlbumTransfer = async (albumId: string): Promise<AlbumTransferDto> => {
  const data = await requestJson<unknown>(`/albums/${albumId}/transfer/cancel`, { method: 'POST' });
  return normalizeTransfer(data);
};

export const acceptAlbumTransfer = async (transferId: string): Promise<AlbumTransferDto> => {
  const data = await requestJson<unknown>(`/album-transfers/${transferId}/accept`, { method: 'POST' });
  return normalizeTransfer(data);
};

export const declineAlbumTransfer = async (transferId: string): Promise<AlbumTransferDto> => {
  const data = await requestJson<unknown>(`/album-transfers/${transferId}/decline`, { method: 'POST' });
  return normalizeTransfer(data);
};

export const isPendingTransfer = (transfer: AlbumTransferDto | null | undefined): transfer is AlbumTransferDto => {
  return !!transfer && transfer.status === AlbumTransferStatus.Pending;
};

export const getAlbumTransferErrorCode = (error: unknown): string => {
  if (error instanceof AlbumTransferApiError && error.code) {
    return error.code;
  }

  const message = (error as Error)?.message || '';
  if (typeof message === 'string') {
    return message;
  }

  return '';
};
