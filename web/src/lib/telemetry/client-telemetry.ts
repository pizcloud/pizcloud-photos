import { browser, dev } from '$app/environment';
import { env } from '$env/dynamic/public';

type TelemetryFetchOptions = {
  eventName?: string;
  fetchFn?: typeof fetch;
  disableFallback?: boolean;
};

type TelemetryMeta = {
  requestId: string;
  correlationId: string;
  eventId: string;
  sessionId: string;
};

const TELEMETRY_ENABLED_STORAGE_KEY = 'pizcloud.telemetry.enabled';
const TELEMETRY_CONSOLE_ENABLED_STORAGE_KEY = 'pizcloud.telemetry.console_enabled';
const CORRELATION_ID_STORAGE_KEY = 'pizcloud.telemetry.correlation_id';
const SESSION_ID_STORAGE_KEY = 'pizcloud.telemetry.session_id';
const DEFAULT_PLATFORM = 'web';
const UNKNOWN_VALUE = 'unknown';
const MAX_EVENT_NAME_LENGTH = 128;
const REQUEST_ID_HEADER = 'x-request-id';
const CORRELATION_ID_HEADER = 'x-correlation-id';
const CLIENT_EVENT_ID_HEADER = 'x-client-event-id';
const CLIENT_SESSION_ID_HEADER = 'x-client-session-id';
const EVENT_NAME_INVALID_CHARACTERS = /[^a-zA-Z0-9._-]/g;
const EMAIL_PATTERN = /\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b/g;
const BEARER_TOKEN_PATTERN = /\bBearer\s+[A-Za-z0-9\-._~+/]+=*\b/gi;
const JWT_PATTERN = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g;

const isTruthy = (value: string | undefined, fallback: boolean) => {
  if (!value) {
    return fallback;
  }

  const normalized = value.trim().toLowerCase();
  if (!normalized) {
    return fallback;
  }

  if (normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on') {
    return true;
  }

  if (normalized === '0' || normalized === 'false' || normalized === 'no' || normalized === 'off') {
    return false;
  }

  return fallback;
};

const readStorageValue = (key: string) => {
  if (!browser) {
    return '';
  }

  try {
    return globalThis.localStorage.getItem(key) || '';
  } catch {
    return '';
  }
};

const writeSessionValue = (key: string, value: string) => {
  if (!browser || !value) {
    return;
  }

  try {
    globalThis.sessionStorage.setItem(key, value);
  } catch {
    // fail-open
  }
};

const readSessionValue = (key: string) => {
  if (!browser) {
    return '';
  }

  try {
    return globalThis.sessionStorage.getItem(key) || '';
  } catch {
    return '';
  }
};

const createId = (prefix: string) => {
  try {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return `${prefix}_${crypto.randomUUID()}`;
    }
  } catch {
    // fallback below
  }

  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
};

const ensureExistingHeader = (headers: Headers, key: string, fallbackFactory: () => string) => {
  const existing = headers.get(key)?.trim();
  if (existing) {
    return existing;
  }

  const next = fallbackFactory();
  headers.set(key, next);
  return next;
};

const buildTelemetryBaseHeaders = () => {
  const envAppVersion = (env.PUBLIC_PIZCLOUD_CLIENT_APP_VERSION || '').trim();
  const envBuildNumber = (env.PUBLIC_PIZCLOUD_CLIENT_BUILD_NUMBER || '').trim();
  const appVersion = envAppVersion || readStorageValue('appVersion') || UNKNOWN_VALUE;
  const buildNumber = envBuildNumber || readStorageValue('buildNumber') || UNKNOWN_VALUE;

  return {
    'x-client-platform': DEFAULT_PLATFORM,
    'x-client-app-version': appVersion,
    'x-client-build-number': buildNumber,
  };
};

const normalizeHeaders = (input?: RequestInfo | URL, init?: RequestInit) => {
  const headers = new Headers(input instanceof Request ? input.headers : undefined);
  const initHeaders = new Headers(init?.headers);

  for (const [key, value] of initHeaders.entries()) {
    headers.set(key, value);
  }

  return headers;
};

const readBooleanOverride = (storageKey: string) => {
  const raw = readStorageValue(storageKey);
  if (!raw) {
    return undefined;
  }
  return isTruthy(raw, true);
};

let memoryCorrelationId = '';
let memorySessionId = '';

export const isClientTelemetryEnabled = () => {
  const envEnabled = isTruthy(env.PUBLIC_PIZCLOUD_CLIENT_TELEMETRY_ENABLED, true);
  const overrideEnabled = readBooleanOverride(TELEMETRY_ENABLED_STORAGE_KEY);
  if (overrideEnabled !== undefined) {
    return envEnabled && overrideEnabled;
  }
  return envEnabled;
};

const isClientTelemetryConsoleEnabled = () => {
  if (!isClientTelemetryEnabled()) {
    return false;
  }

  const envEnabled = isTruthy(env.PUBLIC_PIZCLOUD_CLIENT_TELEMETRY_CONSOLE_ENABLED, dev);
  const overrideEnabled = readBooleanOverride(TELEMETRY_CONSOLE_ENABLED_STORAGE_KEY);
  if (overrideEnabled !== undefined) {
    return envEnabled && overrideEnabled;
  }

  return envEnabled;
};

export const getOrCreateCorrelationId = () => {
  if (memoryCorrelationId) {
    return memoryCorrelationId;
  }

  const fromSession = readSessionValue(CORRELATION_ID_STORAGE_KEY);
  if (fromSession) {
    memoryCorrelationId = fromSession;
    return fromSession;
  }

  const next = createId('cid');
  memoryCorrelationId = next;
  writeSessionValue(CORRELATION_ID_STORAGE_KEY, next);
  return next;
};

export const getOrCreateSessionId = () => {
  if (memorySessionId) {
    return memorySessionId;
  }

  const fromSession = readSessionValue(SESSION_ID_STORAGE_KEY);
  if (fromSession) {
    memorySessionId = fromSession;
    return fromSession;
  }

  const next = createId('sid');
  memorySessionId = next;
  writeSessionValue(SESSION_ID_STORAGE_KEY, next);
  return next;
};

export const createClientEventId = () => createId('evt');
export const createRequestId = () => createId('req');

const normalizeEventName = (eventName?: string) => {
  const normalized = (eventName || '').trim();
  if (!normalized) {
    return '';
  }

  const truncated = normalized.length > MAX_EVENT_NAME_LENGTH ? normalized.slice(0, MAX_EVENT_NAME_LENGTH) : normalized;
  const sanitized = truncated.replace(EVENT_NAME_INVALID_CHARACTERS, '_');
  return sanitized.trim();
};

const redactString = (value: string) => {
  const normalized = value.trim();
  if (!normalized) {
    return normalized;
  }

  if (normalized.includes('@')) {
    const [head, tail = ''] = normalized.split('@');
    if (!head || !tail) {
      return '***';
    }
    return `${head.slice(0, 1)}***@${tail}`;
  }

  if (normalized.length <= 8) {
    return '***';
  }

  return `${normalized.slice(0, 3)}***${normalized.slice(-2)}`;
};

const redactLooseSensitiveString = (value: string) => {
  return value
    .replace(EMAIL_PATTERN, (_value, head: string, tail: string) => `${head}***@${tail}`)
    .replace(BEARER_TOKEN_PATTERN, 'Bearer ***')
    .replace(JWT_PATTERN, '***.***.***');
};

const shouldRedactByKey = (keyPath: string) => {
  const normalized = keyPath.toLowerCase();
  return (
    normalized.includes('token') ||
    normalized.includes('password') ||
    normalized.includes('authorization') ||
    normalized.includes('cookie') ||
    normalized.includes('email') ||
    normalized.includes('purchase') ||
    normalized.includes('orderid') ||
    normalized.includes('order_id')
  );
};

export const redactForTelemetry = (value: unknown, keyPath = ''): unknown => {
  if (value == null) {
    return value;
  }

  if (typeof value === 'string') {
    const redacted = shouldRedactByKey(keyPath) ? redactString(value) : redactLooseSensitiveString(value);
    if (redacted.length > 512) {
      return `${redacted.slice(0, 512)}...[truncated]`;
    }
    return redacted;
  }

  if (typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map((item, index) => redactForTelemetry(item, `${keyPath}[${index}]`));
  }

  if (typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>);
    const output: Record<string, unknown> = {};
    for (const [key, innerValue] of entries) {
      const nextKeyPath = keyPath ? `${keyPath}.${key}` : key;
      output[key] = redactForTelemetry(innerValue, nextKeyPath);
    }
    return output;
  }

  return String(value);
};

const attachTelemetryHeaders = (headers: Headers, eventName?: string): TelemetryMeta | null => {
  if (!isClientTelemetryEnabled()) {
    return null;
  }

  try {
    const requestId = ensureExistingHeader(headers, REQUEST_ID_HEADER, createRequestId);
    const correlationId = ensureExistingHeader(headers, CORRELATION_ID_HEADER, getOrCreateCorrelationId);
    const eventId = ensureExistingHeader(headers, CLIENT_EVENT_ID_HEADER, createClientEventId);
    const sessionId = ensureExistingHeader(headers, CLIENT_SESSION_ID_HEADER, getOrCreateSessionId);

    const baseHeaders = buildTelemetryBaseHeaders();
    for (const [key, value] of Object.entries(baseHeaders)) {
      if (!headers.has(key)) {
        headers.set(key, value);
      }
    }

    const normalizedEventName = normalizeEventName(eventName);
    if (normalizedEventName && !headers.has('x-client-event-name')) {
      headers.set('x-client-event-name', normalizedEventName);
    }

    return { requestId, correlationId, eventId, sessionId };
  } catch {
    return null;
  }
};

export const attachClientTelemetryHeaders = (init?: RequestInit, eventName?: string) => {
  if (!isClientTelemetryEnabled()) {
    return init;
  }

  try {
    const headers = new Headers(init?.headers);
    attachTelemetryHeaders(headers, normalizeEventName(eventName));
    return {
      ...init,
      headers,
    } as RequestInit;
  } catch {
    return init;
  }
};

const toSafePath = (input: RequestInfo | URL) => {
  try {
    const raw = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const baseOrigin = browser ? globalThis.location.origin : 'http://localhost';
    const url = new URL(raw, baseOrigin);
    return `${url.origin}${url.pathname}`;
  } catch {
    return typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
  }
};

const telemetryLog = (level: 'info' | 'warn' | 'error', payload: Record<string, unknown>) => {
  if (!isClientTelemetryConsoleEnabled()) {
    return;
  }

  try {
    const redacted = redactForTelemetry(payload);
    const line = JSON.stringify(redacted);
    const logger = level === 'error' ? console.error : level === 'warn' ? console.warn : console.info;
    logger(`[client.telemetry] ${line}`);
  } catch {
    // fail-open
  }
};

const isLikelyClientTransportError = (error: unknown) => {
  return error instanceof TypeError;
};

type TelemetryRequest = {
  input: RequestInfo | URL;
  init?: RequestInit;
  telemetryMeta: TelemetryMeta | null;
};

const buildTelemetryRequest = (input: RequestInfo | URL, init?: RequestInit, eventName?: string): TelemetryRequest => {
  if (!isClientTelemetryEnabled()) {
    return { input, init, telemetryMeta: null };
  }

  try {
    const headers = normalizeHeaders(input, init);
    const telemetryMeta = attachTelemetryHeaders(headers, eventName);
    const nextInit = {
      ...init,
      headers,
    } satisfies RequestInit;

    if (input instanceof Request) {
      return {
        input: new Request(input, nextInit),
        telemetryMeta,
      };
    }

    return {
      input,
      init: nextInit,
      telemetryMeta,
    };
  } catch {
    return { input, init, telemetryMeta: null };
  }
};

export const fetchWithClientTelemetry = async (
  input: RequestInfo | URL,
  init?: RequestInit,
  options?: TelemetryFetchOptions,
) => {
  const fetchFn = options?.fetchFn ?? fetch;
  if (!browser) {
    return fetchFn(input, init);
  }

  const normalizedEventName = normalizeEventName(options?.eventName);
  const startedAt = Date.now();
  const telemetryRequest = buildTelemetryRequest(input, init, normalizedEventName);
  const method =
    (telemetryRequest.input instanceof Request
      ? telemetryRequest.input.method
      : telemetryRequest.init?.method || init?.method) || 'GET';
  const path = toSafePath(telemetryRequest.input);

  telemetryLog('info', {
    event: 'http.request',
    method,
    path,
    requestId: telemetryRequest.telemetryMeta?.requestId,
    correlationId: telemetryRequest.telemetryMeta?.correlationId,
    clientEventId: telemetryRequest.telemetryMeta?.eventId,
    clientSessionId: telemetryRequest.telemetryMeta?.sessionId,
    clientEventName: normalizedEventName,
  });

  try {
    const response = await fetchFn(telemetryRequest.input, telemetryRequest.init);
    telemetryLog('info', {
      event: 'http.response',
      method,
      path,
      status: response.status,
      durationMs: Date.now() - startedAt,
      requestId: telemetryRequest.telemetryMeta?.requestId,
      correlationId: telemetryRequest.telemetryMeta?.correlationId,
      clientEventId: telemetryRequest.telemetryMeta?.eventId,
      clientSessionId: telemetryRequest.telemetryMeta?.sessionId,
      clientEventName: normalizedEventName,
    });
    return response;
  } catch (error) {
    telemetryLog('error', {
      event: 'http.error',
      method,
      path,
      durationMs: Date.now() - startedAt,
      error: (error as Error)?.message || String(error),
      requestId: telemetryRequest.telemetryMeta?.requestId,
      correlationId: telemetryRequest.telemetryMeta?.correlationId,
      clientEventId: telemetryRequest.telemetryMeta?.eventId,
      clientSessionId: telemetryRequest.telemetryMeta?.sessionId,
      clientEventName: normalizedEventName,
    });

    if (telemetryRequest.telemetryMeta && !options?.disableFallback && isLikelyClientTransportError(error)) {
      return fetchFn(input, init);
    }

    throw error;
  }
};
