import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';

export type SharedEmailDto = {
  email: string;
  createdAt: string;
};

const normalizeBaseUrl = () => (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');

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

export const getSharedEmails = async (albumId: string): Promise<SharedEmailDto[]> => {
  const data = await request(`/albums/${albumId}/shared-emails`, {
    method: 'GET',
    headers: { accept: 'application/json' },
  });

  const items = Array.isArray(data?.items) ? data.items : [];
  return items.map((item: { email?: string; createdAt?: string }) => ({
    email: item.email ?? '',
    createdAt: item.createdAt ?? '',
  }));
};

export const addSharedEmail = async (albumId: string, email: string): Promise<SharedEmailDto[]> => {
  const data = await request(`/albums/${albumId}/shared-emails`, {
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

export const removeSharedEmail = async (albumId: string, email: string): Promise<SharedEmailDto[]> => {
  const data = await request(`/albums/${albumId}/shared-emails`, {
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
