// web/src/routes/(user)/pizcloud/upgrade/+page.ts
import type { StoragePlan } from '$lib/models/pizcloud/billing';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch }) => {
  const res = await fetch('/api/billing/plans');

  if (!res.ok) {
    return {
      plans: [] as StoragePlan[],
      loadError: true,
    };
  }

  const plans = (await res.json()) as StoragePlan[];

  return {
    plans,
    loadError: false,
  };
};
