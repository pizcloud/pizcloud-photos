// web/src/routes/auth/pizcloud/user-register/+page.ts
import { AppRoute } from '$lib/constants';
import { getFormatter } from '$lib/utils/i18n';
import type { PageLoad } from './$types';

export const load = (async ({ url, parent }) => {
  await parent();

  const continueUrl = url.searchParams.get('continue') ?? AppRoute.PHOTOS;

  const $t = await getFormatter();
  return {
    meta: { title: $t('user_registration') },
    continueUrl,
  };
}) satisfies PageLoad;
