import { PUBLIC_DEFAULT_SERVICE_NAME, PUBLIC_MAIN_DOMAIN } from '$env/static/public';
import { defaults, setBaseUrl } from '@immich/sdk';
import { get, writable } from 'svelte/store';

type Fetch = typeof fetch;

const DEFAULT_API_BASE_URL = '/api';
const API_BASE_URL_STORAGE_KEY = 'pizcloud.apiBaseUrl';
const API_SERVICE_STORAGE_KEY = 'pizcloud.apiServiceName';
const API_REFRESH_INTERVAL_MS = 1 * 60 * 1000;

const getDefaultOrigin = () => {
  if (typeof globalThis !== 'undefined' && 'location' in globalThis && globalThis.location?.origin) {
    return globalThis.location.origin;
  }
  return '';
};

const apiBaseUrlStore = writable<string>(DEFAULT_API_BASE_URL);
const apiOriginStoreInternal = writable<string>(getDefaultOrigin());

let refreshTimer: ReturnType<typeof setInterval> | undefined;
let activeServiceName = '';
let refreshInFlight: Promise<void> | null = null;

const isBrowser = () => typeof window !== 'undefined' && typeof localStorage !== 'undefined';

const getAccountUrl = () => `https://account.${PUBLIC_MAIN_DOMAIN}`;

const normalizeApiBaseUrl = (rawUrl: string) => {
  const trimmed = rawUrl.trim();
  if (!trimmed) {
    return DEFAULT_API_BASE_URL;
  }
  const noTrailing = trimmed.replace(/\/+$/, '');
  return noTrailing.endsWith('/api') ? noTrailing : `${noTrailing}/api`;
};

const toOrigin = (baseUrl: string) => {
  const origin = getDefaultOrigin();
  try {
    return new URL(baseUrl, origin || 'http://localhost').origin;
  } catch (error) {
    return origin;
  }
};

const cacheApiBaseUrl = (baseUrl: string, serviceName?: string) => {
  if (!isBrowser()) {
    return;
  }
  localStorage.setItem(API_BASE_URL_STORAGE_KEY, baseUrl);
  if (serviceName) {
    localStorage.setItem(API_SERVICE_STORAGE_KEY, serviceName);
  }
};

const readCachedApiBaseUrl = () => {
  if (!isBrowser()) {
    return '';
  }
  return localStorage.getItem(API_BASE_URL_STORAGE_KEY) || '';
};

const readCachedServiceName = () => {
  if (!isBrowser()) {
    return '';
  }
  return localStorage.getItem(API_SERVICE_STORAGE_KEY) || '';
};

const applyApiBaseUrl = (baseUrl: string, serviceName?: string) => {
  const normalized = normalizeApiBaseUrl(baseUrl);
  if (!defaults.fetch) {
    defaults.fetch = fetch;
  }
  const originalFetch = defaults.fetch;
  defaults.fetch = (input, init) =>
    originalFetch(input, {
      ...init,
      credentials: init?.credentials ?? 'include',
    });
  setBaseUrl(normalized);

  apiBaseUrlStore.set(normalized);
  apiOriginStoreInternal.set(toOrigin(normalized));
  cacheApiBaseUrl(normalized, serviceName);
};

const resolveServiceName = (url: URL) => {
  const paramServiceName = url.searchParams.get('service') || '';
  return paramServiceName || readCachedServiceName() || PUBLIC_DEFAULT_SERVICE_NAME;
};

const requestServiceHealth = async (serviceName: string, fetchFn: Fetch) => {
  const url = `${getAccountUrl()}/api/health/service?service=${encodeURIComponent(serviceName)}`;
  const response = await fetchFn(url, { credentials: 'include' });
  if (!response.ok) {
    throw new Error(`Account health check failed (${response.status})`);
  }
  const data = (await response.json()) as { url?: string };
  return data.url || '';
};

const refreshApiBaseUrl = async (serviceName: string, fetchFn: Fetch) => {
  if (refreshInFlight) {
    return refreshInFlight;
  }

  refreshInFlight = (async () => {
    try {
      const url = await requestServiceHealth(serviceName, fetchFn);
      if (!url) {
        return;
      }
      const normalized = normalizeApiBaseUrl(url);
      if (normalized !== get(apiBaseUrlStore)) {
        applyApiBaseUrl(normalized, serviceName);
      }
    } catch (error) {
      console.warn('Failed to refresh API base URL', error);
    }
  })();

  try {
    await refreshInFlight;
  } finally {
    refreshInFlight = null;
  }
};

const startRefreshTimer = (serviceName: string, fetchFn: Fetch) => {
  if (refreshTimer && activeServiceName === serviceName) {
    return;
  }

  if (refreshTimer) {
    clearInterval(refreshTimer);
  }

  activeServiceName = serviceName;
  refreshTimer = setInterval(() => {
    void refreshApiBaseUrl(serviceName, fetchFn);
  }, API_REFRESH_INTERVAL_MS);
};

export const initApiBaseUrl = async ({ fetch: fetchFn, url }: { fetch: Fetch; url: URL }) => {
  const cachedBaseUrl = readCachedApiBaseUrl();
  if (cachedBaseUrl) {
    applyApiBaseUrl(cachedBaseUrl);
  } else {
    applyApiBaseUrl(DEFAULT_API_BASE_URL);
  }

  const serviceName = resolveServiceName(url);
  if (!serviceName) {
    return;
  }

  await refreshApiBaseUrl(serviceName, fetchFn);
  startRefreshTimer(serviceName, fetchFn);
};

export const getApiBaseUrl = () => get(apiBaseUrlStore);

export const getApiOrigin = () => get(apiOriginStoreInternal);

export const apiOriginStore = apiOriginStoreInternal;
