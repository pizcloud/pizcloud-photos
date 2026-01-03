<script lang="ts">
  import { locale } from '$lib/stores/preferences.store';
  import type { BillingProduct } from '$lib/types/pizcloud/billing';
  import { t } from 'svelte-i18n';

  let { product, selected, onSelect } = $props<{
    product: BillingProduct;
    selected: boolean;
    onSelect: (id: string) => void;
  }>();

  const nf = $derived(
    new Intl.NumberFormat($locale || 'vi-VN', { style: 'currency', currency: 'USD', maximumFractionDigits: 1 }),
  );

  const storageLabel = $derived(
    product.storageLimitGb >= 1000 ? `${product.storageLimitGb / 1000} TB` : `${product.storageLimitGb} GB`,
  );
  const periodLabel = $derived(
    product.period === 'monthly' ? $t('billing.billing_monthly') : $t('billing.billing_yearly'),
  );
  const mlLabel = $derived($t('billing.ml_tier', { values: { tier: product.mlTier } }));

  const discount = '30';
  // const discount = $derived(
  //   (product as unknown as Record<string, unknown>)['discountPercent'] ??
  //     (product as unknown as Record<string, unknown>)['discount'] ??
  //     null,
  // );

  const popular = $derived(
    Boolean(
      (product as unknown as Record<string, unknown>)['isPopular'] ??
        (product as unknown as Record<string, unknown>)['mostPopular'],
    ),
  );
</script>

<button
  type="button"
  class={[
    'w-full text-left rounded-3xl border transition',
    'bg-white/70 dark:bg-immich-dark-primary/20 backdrop-blur',
    'hover:shadow-sm hover:-translate-y-[1px]',
    'focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40',
    selected
      ? 'border-primary ring-2 ring-primary/25 shadow-sm'
      : 'border-gray-200 dark:border-gray-700 hover:border-primary/40',
  ].join(' ')}
  onclick={() => onSelect(product.id)}
>
  <div class="p-4">
    <div class="flex items-start justify-between gap-3">
      <div>
        <div class="flex flex-wrap items-center gap-2">
          <div class="text-lg font-extrabold text-gray-900 dark:text-white">
            {product.mlTierName}
          </div>

          {#if popular}
            <span class="rounded-full bg-primary/10 text-primary px-2.5 py-1 text-[11px] font-extrabold">
              {$t('billing.most_popular')}
            </span>
          {/if}

          {#if discount}
            <span
              class="rounded-full bg-emerald-100 text-emerald-700 px-2.5 py-1 text-[11px] font-extrabold dark:bg-emerald-900/30 dark:text-emerald-200"
            >
              -{discount}%
            </span>
          {/if}
        </div>

        <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">
          <span class="font-semibold text-gray-900 dark:text-white">{product.planCode}</span>
        </div>
      </div>

      <div class="text-right">
        <div class="text-2xl font-extrabold text-gray-900 dark:text-white leading-none">
          {nf.format(product.priceUsd)}
        </div>
        <div class="mt-1 text-xs text-gray-500 dark:text-gray-400">
          {product.period === 'monthly' ? $t('billing.per_month') : $t('billing.per_year')}
        </div>
      </div>
    </div>
    <div
      class={[
        'mt-4 rounded-2xl px-4 py-3 text-center text-sm font-extrabold transition',
        selected
          ? 'bg-primary text-white'
          : 'border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 text-gray-900 dark:text-white hover:bg-gray-50 dark:hover:bg-gray-800/30',
      ].join(' ')}
    >
      {selected ? $t('selected') : $t('billing.select_plan')}
    </div>
  </div>
</button>
