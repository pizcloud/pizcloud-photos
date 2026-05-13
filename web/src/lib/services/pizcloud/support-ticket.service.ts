import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
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

const normalizeBaseUrl = () => {
  const healthBaseUrl = getPizcloudApiBaseUrl();
  const fallbackBaseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
  return (healthBaseUrl || fallbackBaseUrl).replace(/\/+$/, '');
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
    id: asString(input.id ?? input._id),
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
      const messageRaw = parsed.message;
      if (typeof messageRaw === 'string' && messageRaw.trim()) {
        return { message: messageRaw.trim(), code: messageRaw.trim() };
      }

      if (Array.isArray(messageRaw) && messageRaw.length > 0) {
        const first = messageRaw[0];
        if (typeof first === 'string' && first.trim()) {
          return { message: first.trim(), code: first.trim() };
        }
      }
    }
  } catch {
    // Fallback to plain text
  }

  return { message: text };
};

const request = async (path: string, init?: RequestInit): Promise<Response> => {
  const baseUrl = normalizeBaseUrl();
  if (!baseUrl) {
    throw new SupportTicketApiError('Missing pizcloud server url', 0);
  }

  return fetch(`${baseUrl}${path}`, {
    credentials: 'include',
    ...init,
  });
};

const requestJson = async <T>(path: string, init?: RequestInit): Promise<T> => {
  const response = await request(path, init);
  if (!response.ok) {
    const parsedError = await parseErrorBody(response);
    throw new SupportTicketApiError(parsedError.message, response.status, parsedError.code);
  }

  return (await response.json()) as T;
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

  for (const file of input.attachments || []) {
    form.append('attachments', file);
  }

  const payload = await requestJson<Record<string, unknown>>('/support/tickets', {
    method: 'POST',
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

  for (const file of input.attachments || []) {
    form.append('attachments', file);
  }

  const payload = await requestJson<Record<string, unknown>>(
    `/support/tickets/${encodeURIComponent(normalizedTicketId)}/messages`,
    {
      method: 'POST',
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
    headers: {
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({ status }),
  });
};
