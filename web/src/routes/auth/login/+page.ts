import { AppRoute } from '$lib/constants';
import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const load = (async ({ parent, url }) => {
  await parent();

  // pizcloud
  redirect(301, AppRoute.AUTH_LOGIN);

  // if (!serverConfigManager.value.isInitialized) {
  //   // Admin not registered
  //   redirect(302, AppRoute.AUTH_REGISTER);
  // }

  // const $t = await getFormatter();
  // return {
  //   meta: {
  //     title: $t('login'),
  //   },
  //   continueUrl: url.searchParams.get('continue') || AppRoute.PHOTOS,
  // };
  // #pizcloud
}) satisfies PageLoad;
