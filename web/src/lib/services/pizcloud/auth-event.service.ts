import { browser } from '$app/environment';
import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
import { fetchWithClientTelemetry } from '$lib/telemetry/client-telemetry';
import { getPizcloudApiBaseUrl } from '$lib/utils/api-base';

type AuthEventName =
  | 'auth.login.result.success'
  | 'auth.login.result.failure'
  | 'auth.logout.result.success'
  | 'auth.logout.result.failure';

type AuthEventMethod = 'account_session' | 'session_logout';

type AuthEventPayload = {
  event: AuthEventName;
  method: AuthEventMethod;
  occurredAt: string;
  reasonCode?: string;
  source?: string;
  userId?: string;
};

const AUTH_EVENT_ENDPOINT = '/auth/client-events';
const AUTH_LOGIN_RESULT_MARKER_KEY = 'pizcloud.auth.login.result';

const normalizeBaseUrl = () => {
  const healthBaseUrl = getPizcloudApiBaseUrl();
  const fallbackBaseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
  return (healthBaseUrl || fallbackBaseUrl).replace(/\/+$/, '');
};

const readMarker = () => {
  if (!browser) {
    return '';
  }

  try {
    return globalThis.sessionStorage.getItem(AUTH_LOGIN_RESULT_MARKER_KEY) || '';
  } catch {
    return '';
  }
};

const writeMarker = (value: string) => {
  if (!browser) {
    return;
  }

  try {
    globalThis.sessionStorage.setItem(AUTH_LOGIN_RESULT_MARKER_KEY, value);
  } catch {
    // fail-open
  }
};

const removeMarker = () => {
  if (!browser) {
    return;
  }

  try {
    globalThis.sessionStorage.removeItem(AUTH_LOGIN_RESULT_MARKER_KEY);
  } catch {
    // fail-open
  }
};

const reportAuthEvent = async (payload: AuthEventPayload) => {
  if (!browser) {
    return;
  }

  const baseUrl = normalizeBaseUrl();
  if (!baseUrl) {
    return;
  }

  try {
    await fetchWithClientTelemetry(
      `${baseUrl}${AUTH_EVENT_ENDPOINT}`,
      {
        method: 'POST',
        credentials: 'include',
        keepalive: true,
        headers: {
          accept: 'application/json',
          'content-type': 'application/json',
        },
        body: JSON.stringify(payload),
      },
      { eventName: payload.event },
    );
  } catch {
    // fail-open
  }
};

export const clearAuthLoginResultMarker = () => {
  removeMarker();
};

export const reportAuthLoginSuccessOnce = ({ userId, source }: { userId: string; source?: string }) => {
  const marker = `success:${userId}`;
  if (readMarker() === marker) {
    return;
  }

  writeMarker(marker);
  void reportAuthEvent({
    event: 'auth.login.result.success',
    method: 'account_session',
    occurredAt: new Date().toISOString(),
    source,
    userId,
  });
};

export const reportAuthLoginFailureOnce = ({ reasonCode, source }: { reasonCode: string; source?: string }) => {
  const marker = `failure:${reasonCode}`;
  if (readMarker() === marker) {
    return;
  }

  writeMarker(marker);
  void reportAuthEvent({
    event: 'auth.login.result.failure',
    method: 'account_session',
    occurredAt: new Date().toISOString(),
    reasonCode,
    source,
  });
};

export const reportAuthLogoutSuccess = ({ source }: { source?: string } = {}) => {
  void reportAuthEvent({
    event: 'auth.logout.result.success',
    method: 'session_logout',
    occurredAt: new Date().toISOString(),
    source,
  });
};

export const reportAuthLogoutFailure = ({ reasonCode, source }: { reasonCode: string; source?: string }) => {
  void reportAuthEvent({
    event: 'auth.logout.result.failure',
    method: 'session_logout',
    occurredAt: new Date().toISOString(),
    reasonCode,
    source,
  });
};
