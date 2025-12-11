<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import UserReferral from '$lib/components/pizcloud/user-referral-page/user-referral.svelte';
  import ShortcutsModal from '$lib/modals/ShortcutsModal.svelte';
  import { Container, IconButton, modalManager } from '@immich/ui';
  import { mdiKeyboard } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();
</script>

<UserPageLayout title={data.meta.title}>
  {#snippet buttons()}
    <IconButton
      shape="round"
      color="secondary"
      variant="ghost"
      icon={mdiKeyboard}
      aria-label={$t('show_keyboard_shortcuts')}
      onclick={() => modalManager.show(ShortcutsModal, {})}
    />
  {/snippet}
  <Container size="medium" center>
    <UserReferral
      keys={data.keys}
      sessions={data.sessions}
      referralCode={data.referral?.referralCode ?? ''}
      totalReferredUsers={data.referral?.totalReferredUsers ?? 0}
      totalCommission={data.referral?.totalCommission ?? 0}
      monthlyStats={data.referral?.monthlyStats ?? []}
      currency={data.referral?.currency ?? 'USD'}
      referrer={data.referral?.referrer ?? null}
      userEmail={data.referralEmail ?? ''}
      availableBalance={data.referral?.availableBalance ?? data.referral?.totalCommission ?? 0}
      pendingWithdrawalAmount={data.referral?.pendingWithdrawalAmount ?? 0}
      totalRequestedWithdrawal={data.referral?.totalRequestedWithdrawal ?? 0}
      totalPaidWithdrawal={data.referral?.totalPaidWithdrawal ?? 0}
      totalRejectedWithdrawal={data.referral?.totalRejectedWithdrawal ?? 0}
      minWithdrawAmount={data.minWithdrawAmount ?? 5}
      payoutMethodUrl="/pizcloud/payout-method"
      withdrawalHistoryUrl="/pizcloud/withdrawals"
    />
  </Container>
</UserPageLayout>
