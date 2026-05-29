import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
import { fetchWithClientTelemetry } from '$lib/telemetry/client-telemetry';
import { getPizcloudApiBaseUrl } from '$lib/utils/api-base';

export const SUPPORT_TICKET_ATTACHMENT_MAX_BYTES = 8 * 1024 * 1024;

export type SupportTicketStatus = 'open' | 'in_progress' | 'waiting_user' | 'resolved' | 'closed';
export type SupportTicketPriority = 'low' | 'normal' | 'high' | 'urgent';
export type SupportTicketCategory = 'bug' | 'billing' | 'account' | 'feature' | 'other';

export type SupportTicketAttachment = {
  id: string;
  fileName: string;
  mimeType: string;
  size: number;
  url: string;
  createdAt?: string;
};

export type SupportTicketSummary = {
  id: string;
  subject: string;
  category: SupportTicketCategory;
  priority: SupportTicketPriority;
  status: SupportTicketStatus;
  latestMessage: string;
  unreadCount: number;
  attachments: SupportTicketAttachment[];
  createdAt?: string;
  updatedAt?: string;
  closedAt?: string;
};

export type SupportTicketMessage = {
  id: string;
  ticketId: string;
  senderType: string;
  message: string;
  attachments: SupportTicketAttachment[];
  createdAt?: string;
};

export type SupportTicketDetail = {
  ticket: SupportTicketSummary;
  messages: SupportTicketMessage[];
};

export type SupportTicketListResponse = {
  items: SupportTicketSummary[];
  pagination: {
    page: number;
    limit: number;
    total: number;
  };
};

export class SupportTicketApiError extends Error {
  status: number;
  code?: string;

  constructor(message: string, status: number, code?: string) {
    super(message);
    this.name = 'SupportTicketApiError';
    this.status = status;
    this.code = code;
  }
}

type CreateSupportTicketInput = {
  subject: string;
  category: SupportTicketCategory;
  priority: SupportTicketPriority;
  message: string;
  attachments?: File[];
};

type ReplySupportTicketInput = {
  ticketId: string;
  message: string;
  attachments?: File[];
};

type GetSupportTicketsInput = {
  page?: number;
  limit?: number;
  status?: 'all' | SupportTicketStatus;
};

type SupportTicketRequestInit = RequestInit & {
  requestId?: string;
  includeRequestIdHeader?: boolean;
};

const normalizeBaseUrl = () => {
  const healthBaseUrl = getPizcloudApiBaseUrl();
  const fallbackBaseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
  return (healthBaseUrl || fallbackBaseUrl).replace(/\/+$/, '');
};

const createRequestId = () => {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }

  return `st-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
};

const isObject = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null;
};

const asString = (value: unknown) => {
  if (typeof value === 'string') {
    const normalized = value.trim();
    if (normalized) {
      return normalized;
    }
  }
  return '';
};

const asNumber = (value: unknown, fallback = 0) => {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
};

const getFileExtension = (value: string) => {
  const normalized = asString(value);
  const dotIndex = normalized.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === normalized.length - 1) {
    return '';
  }
  return normalized.slice(dotIndex + 1).toLowerCase();
};

const IMAGE_ATTACHMENT_EXTENSIONS = new Set([
  'apng',
  'avif',
  'bmp',
  'gif',
  'heic',
  'heif',
  'jfif',
  'jpeg',
  'jpg',
  'png',
  'svg',
  'tif',
  'tiff',
  'webp',
]);

const normalizeCategory = (value: string): SupportTicketCategory => {
  const candidate = value.toLowerCase();
  switch (candidate) {
    case 'bug':
    case 'billing':
    case 'account':
    case 'feature':
    case 'other':
      return candidate;
    default:
      return 'other';
  }
};

const normalizePriority = (value: string): SupportTicketPriority => {
  const candidate = value.toLowerCase();
  switch (candidate) {
    case 'low':
    case 'normal':
    case 'high':
    case 'urgent':
      return candidate;
    default:
      return 'normal';
  }
};

const normalizeStatus = (value: string): SupportTicketStatus => {
  const candidate = value.toLowerCase();
  switch (candidate) {
    case 'open':
    case 'in_progress':
    case 'waiting_user':
    case 'resolved':
    case 'closed':
      return candidate;
    default:
      return 'open';
  }
};

const normalizeAttachment = (input: unknown): SupportTicketAttachment => {
  if (!isObject(input)) {
    return { id: '', fileName: '', mimeType: '', size: 0, url: '' };
  }

  return {
    id: asString(input.id ?? input._id ?? input.attachmentId),
    fileName: asString(input.fileName ?? input.filename ?? input.name),
    mimeType: asString(input.mimeType ?? input.contentType),
    size: asNumber(input.size, 0),
    url: asString(input.url),
    createdAt: asString(input.createdAt) || undefined,
  };
};

const normalizeSummary = (input: unknown): SupportTicketSummary => {
  if (!isObject(input)) {
    return {
      id: '',
      subject: '',
      category: 'other',
      priority: 'normal',
      status: 'open',
      latestMessage: '',
      unreadCount: 0,
      attachments: [],
    };
  }

  const attachmentsRaw = Array.isArray(input.attachments) ? input.attachments : [];

  return {
    id: asString(input.id ?? input._id),
    subject: asString(input.subject),
    category: normalizeCategory(asString(input.category) || 'other'),
    priority: normalizePriority(asString(input.priority) || 'normal'),
    status: normalizeStatus(asString(input.status) || 'open'),
    latestMessage: asString(input.latestMessage ?? input.message),
    unreadCount: Math.max(0, Math.floor(asNumber(input.unreadCount, 0))),
    attachments: attachmentsRaw.map((item) => normalizeAttachment(item)),
    createdAt: asString(input.createdAt) || undefined,
    updatedAt: asString(input.updatedAt) || undefined,
    closedAt: asString(input.closedAt) || undefined,
  };
};

const normalizeMessage = (input: unknown): SupportTicketMessage => {
  if (!isObject(input)) {
    return {
      id: '',
      ticketId: '',
      senderType: 'user',
      message: '',
      attachments: [],
    };
  }

  const attachmentsRaw = Array.isArray(input.attachments) ? input.attachments : [];

  return {
    id: asString(input.id ?? input._id),
    ticketId: asString(input.ticketId),
    senderType: asString(input.senderType ?? input.role) || 'user',
    message: asString(input.message),
    attachments: attachmentsRaw.map((item) => normalizeAttachment(item)),
    createdAt: asString(input.createdAt) || undefined,
  };
};

const parseErrorBody = async (res: Response) => {
  const text = await res.text();
  if (!text) {
    return { message: `Request failed (${res.status})` };
  }

  try {
    const parsed = JSON.parse(text) as unknown;
    if (isObject(parsed)) {
      const codeRaw = parsed.code;
      const code = typeof codeRaw === 'string' && codeRaw.trim() ? codeRaw.trim() : undefined;
      const messageRaw = parsed.message;
      if (typeof messageRaw === 'string' && messageRaw.trim()) {
        return { message: messageRaw.trim(), code: code || messageRaw.trim() };
      }

      if (Array.isArray(messageRaw) && messageRaw.length > 0) {
        const first = messageRaw[0];
        if (typeof first === 'string' && first.trim()) {
          return { message: first.trim(), code: code || first.trim() };
        }
      }

      if (code) {
        return { message: code, code };
      }
    }
  } catch {
    // Fallback to plain text
  }

  return { message: text };
};

const isLikelyBrowserNetworkError = (error: unknown) => {
  return error instanceof TypeError;
};

const request = async (path: string, init?: SupportTicketRequestInit): Promise<Response> => {
  const { requestId, includeRequestIdHeader = false, ...requestInit } = init || {};
  const baseUrl = normalizeBaseUrl();
  if (!baseUrl) {
    throw new SupportTicketApiError('Missing pizcloud server url', 0);
  }

  const resolvedRequestId = requestId || createRequestId();
  const buildHeaders = (withRequestId: boolean) => {
    const headers = new Headers(requestInit.headers);
    if (withRequestId && !headers.has('x-request-id')) {
      headers.set('x-request-id', resolvedRequestId);
    }
    return headers;
  };

  const doFetch = (withRequestId: boolean) => {
    return fetchWithClientTelemetry(
      `${baseUrl}${path}`,
      {
        credentials: 'include',
        ...requestInit,
        headers: buildHeaders(withRequestId),
      },
      {
        eventName: 'support.ticket.api',
        disableFallback: true,
      },
    );
  };

  try {
    return await doFetch(includeRequestIdHeader);
  } catch (error) {
    if (includeRequestIdHeader && isLikelyBrowserNetworkError(error)) {
      // Fallback for environments where CORS preflight doesn't allow `x-request-id` yet.
      return doFetch(false);
    }

    throw error;
  }
};

const requestJson = async <T>(path: string, init?: SupportTicketRequestInit): Promise<T> => {
  const response = await request(path, init);
  if (!response.ok) {
    const parsedError = await parseErrorBody(response);
    throw new SupportTicketApiError(parsedError.message, response.status, parsedError.code);
  }

  return (await response.json()) as T;
};

const resolveAttachmentUrl = (input: string) => {
  const normalizedInput = input.trim();
  if (!normalizedInput) {
    return '';
  }

  if (/^https?:\/\//i.test(normalizedInput)) {
    return normalizedInput;
  }

  const baseUrl = normalizeBaseUrl();
  if (!baseUrl) {
    return normalizedInput;
  }

  if (normalizedInput.startsWith('/')) {
    try {
      const fallbackOrigin = typeof location !== 'undefined' ? location.origin : 'http://localhost';
      const origin = new URL(baseUrl, fallbackOrigin).origin;
      return `${origin}${normalizedInput}`;
    } catch {
      return `${baseUrl}${normalizedInput}`;
    }
  }

  return `${baseUrl}/${normalizedInput.replace(/^\/+/, '')}`;
};

export const isSupportTicketImageAttachment = (attachment: Pick<SupportTicketAttachment, 'mimeType' | 'fileName'>) => {
  const mimeType = asString(attachment.mimeType).toLowerCase();
  if (mimeType.startsWith('image/')) {
    return true;
  }

  return IMAGE_ATTACHMENT_EXTENSIONS.has(getFileExtension(attachment.fileName));
};

export const isSupportTicketAttachmentUrlExpiredCode = (code?: string) => {
  const normalized = asString(code).toUpperCase();
  return normalized === 'ATTACHMENT_URL_EXPIRED' || normalized === 'ATTACHMENT_URL_INVALID';
};

export const fetchSupportTicketAttachmentBlob = async (attachmentUrl: string): Promise<Blob> => {
  const resolvedUrl = resolveAttachmentUrl(attachmentUrl);
  if (!resolvedUrl) {
    throw new SupportTicketApiError('ATTACHMENT_NOT_FOUND', 400, 'ATTACHMENT_NOT_FOUND');
  }

  const response = await fetchWithClientTelemetry(
    resolvedUrl,
    {
      method: 'GET',
      credentials: 'include',
      headers: { accept: '*/*' },
    },
    {
      eventName: 'support.ticket.attachment.download',
    },
  );

  if (!response.ok) {
    const parsedError = await parseErrorBody(response);
    throw new SupportTicketApiError(parsedError.message, response.status, parsedError.code);
  }

  return response.blob();
};

const validateAttachments = (attachments: File[] = []) => {
  for (const file of attachments) {
    if (file.size > SUPPORT_TICKET_ATTACHMENT_MAX_BYTES) {
      throw new SupportTicketApiError('ATTACHMENT_TOO_LARGE', 400, 'ATTACHMENT_TOO_LARGE');
    }
  }
};

const buildClientMeta = () => {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  return {
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
    platform: typeof navigator !== 'undefined' ? navigator.platform : 'web',
    timezone,
    location: typeof globalThis !== 'undefined' && 'location' in globalThis ? globalThis.location?.pathname || '' : '',
    submittedAt: new Date().toISOString(),
  };
};

export const getSupportTickets = async ({
  page = 1,
  limit = 20,
  status = 'all',
}: GetSupportTicketsInput = {}): Promise<SupportTicketListResponse> => {
  const safePage = page < 1 ? 1 : page;
  const safeLimit = Math.min(Math.max(limit, 1), 100);

  const url = new URL('/support/tickets', 'https://pizcloud.local');
  url.searchParams.set('page', String(safePage));
  url.searchParams.set('limit', String(safeLimit));
  if (status && status !== 'all') {
    url.searchParams.set('status', status);
  }

  const payload = await requestJson<{ items?: unknown[]; pagination?: Record<string, unknown> }>(url.pathname + url.search, {
    method: 'GET',
    headers: { accept: 'application/json' },
  });

  const itemsRaw = Array.isArray(payload.items) ? payload.items : [];
  const paginationRaw = isObject(payload.pagination) ? payload.pagination : {};

  return {
    items: itemsRaw.map((item) => normalizeSummary(item)),
    pagination: {
      page: Math.max(1, Math.floor(asNumber(paginationRaw.page, safePage))),
      limit: Math.max(1, Math.floor(asNumber(paginationRaw.limit, safeLimit))),
      total: Math.max(0, Math.floor(asNumber(paginationRaw.total, itemsRaw.length))),
    },
  };
};

export const getSupportTicketDetail = async (ticketId: string): Promise<SupportTicketDetail> => {
  const normalizedTicketId = ticketId.trim();
  if (!normalizedTicketId) {
    throw new SupportTicketApiError('TICKET_NOT_FOUND', 400, 'TICKET_NOT_FOUND');
  }

  const payload = await requestJson<Record<string, unknown>>(`/support/tickets/${encodeURIComponent(normalizedTicketId)}`, {
    method: 'GET',
    headers: { accept: 'application/json' },
  });

  const ticketRaw = isObject(payload.ticket) ? payload.ticket : payload;
  const messagesRaw = Array.isArray(payload.messages) ? payload.messages : [];

  return {
    ticket: normalizeSummary(ticketRaw),
    messages: messagesRaw.map((item) => normalizeMessage(item)),
  };
};

export const createSupportTicket = async (input: CreateSupportTicketInput): Promise<SupportTicketDetail> => {
  const subject = input.subject.trim();
  const message = input.message.trim();

  if (!subject) {
    throw new SupportTicketApiError('SUBJECT_REQUIRED', 400, 'SUBJECT_REQUIRED');
  }

  if (!message) {
    throw new SupportTicketApiError('MESSAGE_REQUIRED', 400, 'MESSAGE_REQUIRED');
  }

  validateAttachments(input.attachments);

  const form = new FormData();
  form.append('subject', subject);
  form.append('category', input.category);
  form.append('priority', input.priority);
  form.append('message', message);
  form.append('meta', JSON.stringify(buildClientMeta()));

  for (const file of Array.from(input.attachments || [])) {
    form.append('attachments', file, file.name);
  }

  const payload = await requestJson<Record<string, unknown>>('/support/tickets', {
    method: 'POST',
    includeRequestIdHeader: true,
    headers: { accept: 'application/json' },
    body: form,
  });

  const ticketRaw = isObject(payload.ticket) ? payload.ticket : payload;
  const messagesRaw = Array.isArray(payload.messages) ? payload.messages : [];

  return {
    ticket: normalizeSummary(ticketRaw),
    messages: messagesRaw.map((item) => normalizeMessage(item)),
  };
};

export const replySupportTicket = async (input: ReplySupportTicketInput): Promise<SupportTicketDetail> => {
  const normalizedTicketId = input.ticketId.trim();
  const message = input.message.trim();

  if (!normalizedTicketId) {
    throw new SupportTicketApiError('TICKET_NOT_FOUND', 400, 'TICKET_NOT_FOUND');
  }

  if (!message) {
    throw new SupportTicketApiError('MESSAGE_REQUIRED', 400, 'MESSAGE_REQUIRED');
  }

  validateAttachments(input.attachments);

  const form = new FormData();
  form.append('message', message);
  form.append('meta', JSON.stringify(buildClientMeta()));

  for (const file of Array.from(input.attachments || [])) {
    form.append('attachments', file, file.name);
  }

  const payload = await requestJson<Record<string, unknown>>(
    `/support/tickets/${encodeURIComponent(normalizedTicketId)}/messages`,
    {
      method: 'POST',
      includeRequestIdHeader: true,
      headers: { accept: 'application/json' },
      body: form,
    },
  );

  const ticketRaw = isObject(payload.ticket) ? payload.ticket : payload;
  const messagesRaw = Array.isArray(payload.messages) ? payload.messages : [];

  return {
    ticket: normalizeSummary(ticketRaw),
    messages: messagesRaw.map((item) => normalizeMessage(item)),
  };
};

export const updateSupportTicketStatus = async (
  ticketId: string,
  status: SupportTicketStatus,
): Promise<void> => {
  const normalizedTicketId = ticketId.trim();

  if (!normalizedTicketId) {
    throw new SupportTicketApiError('TICKET_NOT_FOUND', 400, 'TICKET_NOT_FOUND');
  }

  await requestJson<unknown>(`/support/tickets/${encodeURIComponent(normalizedTicketId)}/status`, {
    method: 'PATCH',
    includeRequestIdHeader: true,
    headers: {
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({ status }),
  });
};
