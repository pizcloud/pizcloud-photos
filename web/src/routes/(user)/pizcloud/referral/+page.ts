import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
import { user } from '$lib/stores/user.store';
import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getApiKeys, getSessions } from '@immich/sdk';
import { get } from 'svelte/store';
import type { PageLoad } from './$types';


interface ReferralMonthlyStat {
  month: string;
  commission: number;
  activeUsers: number;
}

interface ReferralReferrer {
  email: string;
  referralCode?: string | null;
  discountStartAt?: string | null;
  discountEndAt?: string | null;
}

interface ReferralSummary {
  referralCode: string | null;
  totalReferredUsers: number;
  totalCommission: number;
  monthlyStats: ReferralMonthlyStat[];
  currency: string;
  referrer?: ReferralReferrer | null;
}

export const load = (async ({ url, fetch }) => {
  await authenticate(url);

  const [$t, keys, sessions] = await Promise.all([
    getFormatter(),
    getApiKeys(),
    getSessions(),
  ]);

  const userEmail = get(user).email;
  let referral: ReferralSummary | null = null;
  console.log('userEmail', userEmail)

  if (userEmail) {
    const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
    try {
      const res = await fetch(
        `${baseUrl}/papi/referral/summary?email=${encodeURIComponent(userEmail)}`,
        {
          method: 'GET',
          headers: { 'content-type': 'application/json' },
        },
      );

      if (res.ok) {
        referral = (await res.json()) as ReferralSummary;
      } else if (res.status === 404 || res.status === 400) {
        referral = null;
      } else {
        console.error('Failed to load referral summary', res.status, await res.text());
      }
    } catch (error) {
      console.error('Error fetching referral summary', error);
    }
  }

  return {
    keys,
    sessions,
    referral,
    referralEmail: userEmail,
    meta: {
      title: $t('referral_program'),
    },
  };
}) satisfies PageLoad;
