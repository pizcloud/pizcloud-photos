import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getApiKeys, getSessions } from '@immich/sdk';
import type { PageLoad } from './$types';

export const load = (async ({ url, params }) => {
  await authenticate(url);

  const [$t, keys, sessions] = await Promise.all([getFormatter(), getApiKeys(), getSessions()]);

  return {
    keys,
    sessions,
    ticketId: params.ticketId,
    meta: {
      title: $t('support_ticket.detail'),
    },
  };
}) satisfies PageLoad;
