<script lang="ts">
  import type { BillingOrder, BillingProduct } from '$lib/types/pizcloud/billing';
  import { t } from 'svelte-i18n';

  let { orders, productsById, onOpen, onCancel, cancellingId } = $props<{
    orders: BillingOrder[];
    productsById: Record<string, BillingProduct>;
    onOpen: (orderId: string) => void;
    onCancel: (orderId: string) => Promise<void>;
    cancellingId: string | null;
  }>();

  const tone = (s: string) => {
    const u = String(s).toUpperCase();
    if (u === 'PAID')
      return 'bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-900/20 dark:text-emerald-200 dark:border-emerald-900/40';
    if (u === 'EXPIRED')
      return 'bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-900/20 dark:text-rose-200 dark:border-rose-900/40';
    if (u === 'CANCELLED')
      return 'bg-slate-50 text-slate-700 border-slate-200 dark:bg-slate-900/20 dark:text-slate-200 dark:border-slate-900/40';
    return 'bg-amber-50 text-amber-800 border-amber-200 dark:bg-amber-900/20 dark:text-amber-200 dark:border-amber-900/40';
  };

  const fmt = (iso: string) =>
    new Date(iso).toLocaleString(undefined, {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
</script>

<div
  class="mt-8 rounded-3xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-immich-dark-primary/20 p-5 sm:p-6 backdrop-blur"
>
  <div class="flex items-center justify-between gap-3">
    <div>
      <div class="text-lg font-extrabold text-gray-900 dark:text-white">{$t('billing.order_history')}</div>
      <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.order_history_desc')}</div>
    </div>
  </div>

  {#if !orders?.length}
    <div class="mt-4 text-sm text-gray-600 dark:text-gray-300">{$t('billing.no_orders_yet')}</div>
  {:else}
    <div class="mt-4 space-y-3">
      {#each orders as o (o.id)}
        {@const p = productsById[o.productId]}
        <div class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 p-4">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <div class="font-extrabold text-gray-900 dark:text-white truncate">
                  {p ? `${p.planCode} • ${p.storageLimitGb}GB` : o.productId}
                </div>
                <span
                  class={[
                    'inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-bold',
                    tone(o.status),
                  ].join(' ')}
                >
                  {$t('billing.order_status')}: {o.status}
                </span>
              </div>
              <div class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {$t('created_at')}: {fmt(o.createdAt)} • ID: <span class="font-mono">{o.id}</span>
              </div>
            </div>

            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/20 px-4 py-2 text-sm font-extrabold text-gray-900 dark:text-white hover:bg-gray-50 dark:hover:bg-gray-800/30"
                onclick={() => onOpen(o.id)}
              >
                {$t('billing.view_order')}
              </button>

              {#if o.status === 'PENDING'}
                <button
                  type="button"
                  class="rounded-2xl bg-rose-600 px-4 py-2 text-sm font-extrabold text-white hover:opacity-90 disabled:opacity-60"
                  disabled={cancellingId === o.id}
                  onclick={() => onCancel(o.id)}
                >
                  {cancellingId === o.id ? $t('billing.cancelling') : $t('billing.cancel_order')}
                </button>
              {/if}
            </div>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>
