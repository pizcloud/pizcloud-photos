<script lang="ts">
  import { goto } from '$app/navigation'; // pizcloud
  import { locale } from '$lib/stores/preferences.store';
  import { user } from '$lib/stores/user.store';
  import { userInteraction } from '$lib/stores/user.svelte';
  import { requestServerInfo } from '$lib/utils/auth';
  import { getByteUnitString } from '$lib/utils/byte-units';
  import { LoadingSpinner } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  let usageClasses = $state('');

  let hasQuota = $derived($user?.quotaSizeInBytes !== null);
  let availableBytes = $derived((hasQuota ? $user?.quotaSizeInBytes : userInteraction.serverInfo?.diskSizeRaw) || 0);
  let usedBytes = $derived((hasQuota ? $user?.quotaUsageInBytes : userInteraction.serverInfo?.diskUseRaw) || 0);
  let usedPercentage = $derived(Math.min(Math.round((usedBytes / availableBytes) * 100), 100));

  const onUpdate = () => {
    usageClasses = getUsageClass();
  };

  const getUsageClass = () => {
    if (usedPercentage >= 95) {
      return 'bg-red-500';
    }

    if (usedPercentage > 80) {
      return 'bg-yellow-500';
    }

    return 'bg-primary';
  };

  // pizcloud
  // const onUpgradeClick = () => {
  //   goto('/upgrade');
  // };
  const onUpgrade = () => goto('/pizcloud/upgrade');
  // #pizcloud

  $effect(() => {
    if ($user) {
      onUpdate();
    }
  });

  onMount(async () => {
    if (userInteraction.serverInfo && $user) {
      return;
    }
    await requestServerInfo();
  });
</script>

<div
  class="storage-status p-4 bg-gray-100 dark:bg-immich-dark-primary/10 ms-4 rounded-lg text-sm min-w-52"
  title={$t('storage_usage', {
    values: {
      used: getByteUnitString(usedBytes, $locale, 3),
      available: getByteUnitString(availableBytes, $locale, 3),
    },
  })}
>
  <p class="font-medium text-immich-dark-gray dark:text-white mb-2">{$t('storage')}</p>

  {#if userInteraction.serverInfo}
    <p class="text-gray-500 dark:text-gray-300">
      {$t('storage_usage', {
        values: {
          used: getByteUnitString(usedBytes, $locale),
          available: getByteUnitString(availableBytes, $locale),
        },
      })}
    </p>

    <div class="mt-4 h-[7px] w-full rounded-full bg-gray-200 dark:bg-gray-700">
      <div class="h-[7px] rounded-full {usageClasses}" style="width: {usedPercentage}%"></div>
    </div>

    <!-- pizcloud -->
    <div class="mt-3 flex items-center justify-between gap-2">
      <p class="text-xs text-gray-500 dark:text-gray-300">
        {$t('billing.storage_upgrade_cta')}
      </p>

      <button
        type="button"
        class="mt-4 w-full rounded-md bg-primary px-3 py-2 text-white font-medium hover:opacity-90 active:opacity-80 transition"
        onclick={onUpgrade}
      >
        {$t('upgrade')}
      </button>
      <!-- <button
        type="button"
        class="inline-flex items-center rounded-md bg-primary px-3 py-1 text-xs font-medium text-white hover:bg-primary/90 disabled:opacity-60 disabled:cursor-not-allowed"
        onclick={onUpgrade}
      >
        {$t('upgrade')}
      </button> -->
    </div>
    <!-- #pizcloud -->
  {:else}
    <div class="mt-2">
      <LoadingSpinner />
    </div>
  {/if}
</div>
