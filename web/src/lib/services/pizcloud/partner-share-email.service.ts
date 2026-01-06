import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
import { getPizcloudApiBaseUrl } from '$lib/utils/api-base';

export type PartnerSharedEmailDto = {
  email: string;
  createdAt: string;
};

const normalizeBaseUrl = () => {
  // prefer health-check pizcloudApi, fallback to env
  const healthBaseUrl = getPizcloudApiBaseUrl();
  const fallbackBaseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
  return (healthBaseUrl || fallbackBaseUrl).replace(/\/+$/, '');
};

const request = async (path: string, init?: RequestInit) => {
  const baseUrl = normalizeBaseUrl();
  if (!baseUrl) {
    throw new Error('Missing pizcloud server url');
  }

  const res = await fetch(`${baseUrl}${path}`, {
    credentials: 'include',
    ...init,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `Request failed: ${res.status}`);
  }

  return res.json();
};

export const getPartnerSharedEmails = async (): Promise<PartnerSharedEmailDto[]> => {
  const data = await request('/partners/shared-emails', {
    method: 'GET',
    headers: { accept: 'application/json' },
  });

  const items = Array.isArray(data?.items) ? data.items : [];
  return items.map((item: { email?: string; createdAt?: string }) => ({
    email: item.email ?? '',
    createdAt: item.createdAt ?? '',
  }));
};

export const addPartnerSharedEmail = async (email: string): Promise<PartnerSharedEmailDto[]> => {
  const data = await request('/partners/shared-emails', {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ email }),
  });

  const items = Array.isArray(data?.items) ? data.items : [];
  return items.map((item: { email?: string; createdAt?: string }) => ({
    email: item.email ?? '',
    createdAt: item.createdAt ?? '',
  }));
};

export const removePartnerSharedEmail = async (email: string): Promise<PartnerSharedEmailDto[]> => {
  const data = await request('/partners/shared-emails', {
    method: 'DELETE',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ email }),
  });

  const items = Array.isArray(data?.items) ? data.items : [];
  return items.map((item: { email?: string; createdAt?: string }) => ({
    email: item.email ?? '',
    createdAt: item.createdAt ?? '',
  }));
};
