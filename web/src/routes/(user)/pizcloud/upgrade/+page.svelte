<script lang="ts">
  import type { StoragePlan } from '$lib/models/pizcloud/billing';
  import { locale } from '$lib/stores/preferences.store';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  export let data: PageData;

  let isRedirecting = false;
  let errorMessage = '';

  const plans: StoragePlan[] = data.plans ?? [];

  const formatPrice = (plan: StoragePlan, localeValue: string) => {
    const formatted = new Intl.NumberFormat(localeValue, {
      style: 'currency',
      currency: plan.currency,
      maximumFractionDigits: 2,
    }).format(plan.price);

    return formatted;
  };

  const startCheckout = async (planId: string) => {
    if (isRedirecting) return;
    isRedirecting = true;
    errorMessage = '';

    try {
      const res = await fetch('/api/billing/checkout', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ planId }),
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || 'Checkout failed');
      }

      const body = (await res.json()) as { url: string };
      if (!body.url) {
        throw new Error('Missing checkout url');
      }

      // Redirect to Stripe Checkout
      window.location.href = body.url;
    } catch (error) {
      console.error(error);
      errorMessage = $t('billing.payment_error_description');
      isRedirecting = false;
    }
  };
</script>

<svelte:head>
  <title>{$t('billing.plans_title')}</title>
</svelte:head>

<section class="mx-auto max-w-4xl px-4 py-8">
  <h1 class="mb-2 text-2xl font-semibold text-immich-dark-gray dark:text-white">
    {$t('billing.plans_title')}
  </h1>

  <p class="mb-6 text-sm text-gray-600 dark:text-gray-300">
    {$t('billing.plans_subtitle')}
  </p>

  {#if data.loadError}
    <div class="mb-4 rounded-md border border-red-300 bg-red-50 px-4 py-2 text-sm text-red-700">
      {$t('billing.payment_error_title')}
    </div>
  {/if}

  {#if errorMessage}
    <div class="mb-4 rounded-md border border-red-300 bg-red-50 px-4 py-2 text-sm text-red-700">
      {errorMessage}
    </div>
  {/if}

  <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
    {#each plans as plan}
      <article
        class="flex h-full flex-col justify-between rounded-lg border border-gray-200 bg-white p-4 text-sm shadow-sm dark:border-gray-700 dark:bg-immich-dark-primary/70"
      >
        <div>
          <div class="mb-1 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-immich-dark-gray dark:text-white">
              {plan.name}
            </h2>

            {#if plan.recommended}
              <span class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary">
                {$t('billing.most_popular')}
              </span>
            {/if}
          </div>

          <p class="mb-1 text-xs uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {plan.tier}
          </p>

          <p class="mb-3 text-gray-600 dark:text-gray-200">
            {$t('billing.storage_plan_storage_label', {
              values: { amount: `${plan.storageGb} GB` },
            })}
          </p>

          <p class="mb-4 text-xs text-gray-500 dark:text-gray-400">
            {plan.description}
          </p>

          <p class="text-lg font-semibold text-immich-dark-gray dark:text-white">
            {formatPrice(plan, $locale ?? 'en-US')}
            <span class="ml-1 text-xs font-normal text-gray-500 dark:text-gray-300">
              / {plan.interval === 'month' ? $t('billing.billing_period_monthly') : $t('billing.billing_period_yearly')}
            </span>
          </p>
        </div>

        <button
          class="mt-4 w-full rounded-md bg-primary px-3 py-2 text-sm font-medium text-white hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60"
          type="button"
          disabled={isRedirecting}
          on:click={() => startCheckout(plan.id)}
        >
          {isRedirecting ? $t('billing.processing_payment') : $t('billing.buy_now')}
        </button>
      </article>
    {/each}
  </div>
</section>
