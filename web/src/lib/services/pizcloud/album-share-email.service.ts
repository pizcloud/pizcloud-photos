import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
import { getPizcloudApiBaseUrl } from '$lib/utils/api-base';

export type SharedEmailDto = {
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

const requestNoContent = async (path: string, init?: RequestInit): Promise<void> => {
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
};

export const getSharedEmails = async (albumId: string): Promise<SharedEmailDto[]> => {
  const data = await request(`/albums/shared-emails`, {
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
  const data = await request(`/albums/shared-emails`, {
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
  const data = await request(`/albums/shared-emails`, {
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

export const sendAlbumInvitePushByEmails = async (albumId: string, emails: Iterable<string>): Promise<void> => {
  const normalizedEmails = [...new Set([...emails].map((email) => email.trim().toLowerCase()).filter((email) => !!email))];

  if (normalizedEmails.length === 0) {
    return;
  }

  await requestNoContent('/notifications/album-invite', {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ albumId, emails: normalizedEmails }),
  });
};

export const sendAlbumInvitePushByEmailsBestEffort = async (albumId: string, emails: Iterable<string>): Promise<void> => {
  try {
    await sendAlbumInvitePushByEmails(albumId, emails);
  } catch (error) {
    console.warn('sendAlbumInvitePushByEmailsBestEffort failed', error);
  }
};
