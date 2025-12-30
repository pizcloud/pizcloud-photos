import { getApiBaseUrl } from '$lib/utils/api-base';

export type PartnerResolveEmailsResponseDto = {
  userIds: string[];
  missingEmails: string[];
};

export const resolvePartnerShareEmails = async (emails: string[]): Promise<PartnerResolveEmailsResponseDto> => {
  const baseUrl = getApiBaseUrl();
  const res = await fetch(`${baseUrl}/partners/resolve-emails`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ emails }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `Request failed: ${res.status}`);
  }

  const data = (await res.json()) as PartnerResolveEmailsResponseDto;
  return {
    userIds: Array.isArray(data.userIds) ? data.userIds : [],
    missingEmails: Array.isArray(data.missingEmails) ? data.missingEmails : [],
  };
};
