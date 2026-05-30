import { PUBLIC_DEFAULT_SERVICE_NAME, PUBLIC_MAIN_DOMAIN } from '$env/static/public';
import { fetchWithClientTelemetry } from '$lib/telemetry/client-telemetry'; // pizcloud
import { defaults, setBaseUrl } from '@immich/sdk';
import { get, writable } from 'svelte/store';

type Fetch = typeof fetch;

const DEFAULT_API_BASE_URL = '/api';
const API_BASE_URL_STORAGE_KEY = 'pizcloud.apiBaseUrl';
const PIZCLOUD_API_STORAGE_KEY = 'pizcloud.pizcloudApi';
const API_SERVICE_STORAGE_KEY = 'pizcloud.apiServiceName';
const API_REFRESH_INTERVAL_MS = 3 * 60 * 1000;

const getDefaultOrigin = () => {
  if (typeof globalThis !== 'undefined' && 'location' in globalThis && globalThis.location?.origin) {
    return globalThis.location.origin;
  }
  return '';
};

const apiBaseUrlStore = writable<string>(DEFAULT_API_BASE_URL);
const pizcloudApiStore = writable<string>('');
const apiOriginStoreInternal = writable<string>(getDefaultOrigin());

let refreshTimer: ReturnType<typeof setInterval> | undefined;
let activeServiceName = '';
let refreshInFlight: Promise<void> | null = null;
let sdkRawFetch: Fetch | null = null; // pizcloud

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

const normalizePizcloudApiUrl = (rawUrl: string) => {
  const trimmed = rawUrl.trim();
  if (!trimmed) {
    return '';
  }
  return trimmed.replace(/\/+$/, '');
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

const cachePizcloudApiBaseUrl = (baseUrl: string) => {
  if (!isBrowser()) {
    return;
  }
  localStorage.setItem(PIZCLOUD_API_STORAGE_KEY, baseUrl);
};

const readCachedPizcloudApiBaseUrl = () => {
  if (!isBrowser()) {
    return '';
  }
  return localStorage.getItem(PIZCLOUD_API_STORAGE_KEY) || '';
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
  // pizcloud
  sdkRawFetch ??= defaults.fetch;
  const originalFetch = sdkRawFetch;
  defaults.fetch = (input, init) => {
    const nextInit = {
      ...init,
      credentials: init?.credentials ?? 'include',
    };

    return fetchWithClientTelemetry(input, nextInit, {
      fetchFn: originalFetch,
      eventName: 'internal.photo_api.request',
    });
  };
  // #pizcloud
  setBaseUrl(normalized);

  apiBaseUrlStore.set(normalized);
  apiOriginStoreInternal.set(toOrigin(normalized));
  cacheApiBaseUrl(normalized, serviceName);
};

const applyPizcloudApiBaseUrl = (baseUrl: string) => {
  const normalized = normalizePizcloudApiUrl(baseUrl);
  if (!normalized) {
    return;
  }
  pizcloudApiStore.set(normalized);
  cachePizcloudApiBaseUrl(normalized);
};

const resolveServiceName = (url: URL) => {
  const paramServiceName = url.searchParams.get('service') || '';
  return paramServiceName || PUBLIC_DEFAULT_SERVICE_NAME || readCachedServiceName();
};

const requestServiceHealth = async (serviceName: string, fetchFn: Fetch) => {
  const url = `${getAccountUrl()}/api/health/service?service=${encodeURIComponent(serviceName)}`;
  const response = await fetchWithClientTelemetry(
    url,
    { credentials: 'include' },
    { fetchFn, eventName: 'external.health.service_lookup' },
  ); // pizcloud
  if (!response.ok) {
    throw new Error(`Account health check failed (${response.status})`);
  }
  const data = (await response.json()) as { photoApi?: string; pizcloudApi?: string };
  return {
    photoApi: data.photoApi || '',
    pizcloudApi: data.pizcloudApi || '',
  };
};

const refreshApiBaseUrl = async (serviceName: string, fetchFn: Fetch) => {
  if (refreshInFlight) {
    return refreshInFlight;
  }

  refreshInFlight = (async () => {
    try {
      const { photoApi, pizcloudApi } = await requestServiceHealth(serviceName, fetchFn);
      if (photoApi) {
        const normalized = normalizeApiBaseUrl(photoApi);
        if (normalized !== get(apiBaseUrlStore)) {
          applyApiBaseUrl(normalized, serviceName);
        }
      }
      if (pizcloudApi) {
        applyPizcloudApiBaseUrl(pizcloudApi);
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
  const cachedPizcloudApi = readCachedPizcloudApiBaseUrl();
  if (cachedPizcloudApi) {
    applyPizcloudApiBaseUrl(cachedPizcloudApi);
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

export const getPizcloudApiBaseUrl = () => get(pizcloudApiStore);
