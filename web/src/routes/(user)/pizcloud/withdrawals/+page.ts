// web/src/routes/(user)/pizcloud/withdrawals/+page.ts
import { user } from '$lib/stores/user.store';
import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getApiKeys, getSessions } from '@immich/sdk';
import { get } from 'svelte/store';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  await authenticate(url);

  const [$t, keys, sessions] = await Promise.all([
    getFormatter(),
    getApiKeys(),
    getSessions(),
  ]);

  const userEmail = get(user).email;

  return {
    keys,
    sessions,
    userEmail,
    meta: {
      title: $t('referral.withdraw_history_title'),
    },
  };
}) satisfies PageLoad;
