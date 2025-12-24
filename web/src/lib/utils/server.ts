import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
import { serverConfigManager } from '$lib/managers/server-config-manager.svelte';
import { initApiBaseUrl } from '$lib/utils/api-base';
import { initLanguage } from '$lib/utils';
import { defaults } from '@immich/sdk';
import { memoize } from 'lodash-es';

type Fetch = typeof fetch;

async function _init(fetch: Fetch, url: URL) {
  // set event.fetch on the fetch-client used by @immich/sdk
  // https://kit.svelte.dev/docs/load#making-fetch-requests
  // https://github.com/oazapfts/oazapfts/blob/main/README.md#fetch-options
  defaults.fetch = fetch;
  await initApiBaseUrl({ fetch, url });
  await initLanguage();
  await serverConfigManager.init();

  if (!serverConfigManager.value.maintenanceMode) {
    await featureFlagsManager.init();
  }
}

export const init = memoize(_init, () => 'singlevalue');
