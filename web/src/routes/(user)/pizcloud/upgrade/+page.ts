// web/src/routes/(user)/pizcloud/upgrade/+page.ts

import { user } from '$lib/stores/user.store';
import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getBillingProducts } from '$lib/utils/pizcloud/billing-api';
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
  const products = await getBillingProducts(fetch);

  return {
    keys,
    sessions,
    userEmail,
    meta: {
      title: $t('billing.upgrade_storage'),
    },
    products
  };
}) satisfies PageLoad;

