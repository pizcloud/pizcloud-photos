import { fetchWithClientTelemetry } from '$lib/telemetry/client-telemetry';
import { getApiBaseUrl } from '$lib/utils/api-base';

export type AlbumResolveEmailsResponseDto = {
  userIds: string[];
  missingEmails: string[];
};

export const resolveAlbumShareEmails = async (
  albumId: string,
  emails: string[],
): Promise<AlbumResolveEmailsResponseDto> => {
  const baseUrl = getApiBaseUrl();
  const res = await fetchWithClientTelemetry(
    `${baseUrl}/albums/${albumId}/resolve-emails`,
    {
      method: 'POST',
      credentials: 'include',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ emails }),
    },
    { eventName: 'album.share_emails.resolve' },
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `Request failed: ${res.status}`);
  }

  const data = (await res.json()) as AlbumResolveEmailsResponseDto;
  return {
    userIds: Array.isArray(data.userIds) ? data.userIds : [],
    missingEmails: Array.isArray(data.missingEmails) ? data.missingEmails : [],
  };
}; 
