<script lang="ts">
  import { locale } from '$lib/stores/preferences.store';
  import type { BillingOrder } from '$lib/types/pizcloud/billing';
  import { t } from 'svelte-i18n';

  let { order, onRefresh, refreshing, onCancel, cancelling, error } = $props<{
    order: BillingOrder;
    onRefresh: () => Promise<void>;
    onCancel: () => Promise<void>;
    refreshing: boolean;
    cancelling: boolean;
    error: string | null;
  }>();

  let copiedKey = $state<string | null>(null);

  const nf = $derived(
    new Intl.NumberFormat($locale || 'vi-VN', { style: 'currency', currency: 'USD', maximumFractionDigits: 1 }),
  );

  const expiresLabel = $derived(
    new Date(order.expiresAt).toLocaleString($locale || 'vi-VN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    }),
  );

  const statusTone = $derived.by(() => {
    const s = String(order.status || '').toUpperCase();
    if (s === 'PAID')
      return 'bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-900/20 dark:text-emerald-200 dark:border-emerald-900/40';
    if (s === 'EXPIRED' || s === 'CANCELLED')
      return 'bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-900/20 dark:text-rose-200 dark:border-rose-900/40';
    return 'bg-amber-50 text-amber-800 border-amber-200 dark:bg-amber-900/20 dark:text-amber-200 dark:border-amber-900/40';
  });

  async function copy(text: string, key: string) {
    await navigator.clipboard.writeText(text);
    copiedKey = key;
    setTimeout(() => (copiedKey = null), 1000);
  }
</script>

<div
  class="rounded-3xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-immich-dark-primary/20 p-5 sm:p-6 backdrop-blur"
>
  <!-- Header -->
  <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
    <div>
      <div class="flex flex-wrap items-center gap-2">
        <div class="text-lg font-extrabold text-gray-900 dark:text-white">
          {$t('billing.bank_transfer_instructions')}
        </div>

        <span
          class={['inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-bold', statusTone].join(' ')}
        >
          {$t('billing.order_status')}: {order.status}
        </span>
      </div>

      <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">
        {$t('billing.bank_transfer_hint')}
      </div>
    </div>

    <!-- <div class="flex flex-col items-start sm:items-end gap-1 text-xs text-gray-500 dark:text-gray-400">
      <div
        class="inline-flex items-center gap-2 rounded-xl border border-gray-200 dark:border-gray-700 bg-white/50 dark:bg-gray-900/20 px-3 py-2"
      >
        <span class="opacity-70">{$t('billing.expires_at')}:</span>
        <span class="font-semibold text-gray-900 dark:text-white">{expiresLabel}</span>
      </div>
      <div
        class="inline-flex items-center gap-2 rounded-xl border border-gray-200 dark:border-gray-700 bg-white/50 dark:bg-gray-900/20 px-3 py-2"
      >
        <span class="opacity-70">{$t('billing.order_id')}:</span>
        <span class="font-mono text-gray-900 dark:text-white">{order.id}</span>
      </div>
    </div> -->

    <div class="flex flex-col items-start sm:items-end gap-2">
      <div
        class="inline-flex items-center gap-2 rounded-xl border border-gray-200 dark:border-gray-700 bg-white/50 dark:bg-gray-900/20 px-3 py-2 text-xs text-gray-500 dark:text-gray-400"
      >
        <span class="opacity-70">{$t('billing.expires_at')}:</span>
        <span class="font-semibold text-gray-900 dark:text-white">{expiresLabel}</span>
      </div>

      <div
        class="inline-flex items-center gap-2 rounded-xl border border-gray-200 dark:border-gray-700 bg-white/50 dark:bg-gray-900/20 px-3 py-2 text-xs text-gray-500 dark:text-gray-400"
      >
        <span class="opacity-70">{$t('billing.order_id')}:</span>
        <span class="font-mono text-gray-900 dark:text-white">{order.id}</span>
      </div>

      {#if order.status === 'PENDING'}
        <button
          type="button"
          class="mt-1 rounded-xl bg-rose-600 px-4 py-2 text-xs font-extrabold text-white hover:opacity-90 disabled:opacity-60"
          disabled={cancelling}
          onclick={onCancel}
        >
          {cancelling ? $t('billing.cancelling') : $t('billing.cancel_order')}
        </button>
      {/if}
    </div>
  </div>

  <!-- Summary -->
  <div class="mt-5 grid gap-3 lg:grid-cols-3">
    <div class="rounded-2xl border border-primary/20 bg-primary/5 dark:bg-primary/10 p-4">
      <div class="text-xs font-semibold text-gray-700 dark:text-gray-200">{$t('billing.amount')}</div>
      <div class="mt-1 text-2xl font-extrabold text-gray-900 dark:text-white">
        {nf.format(order.amountVnd)}
      </div>
    </div>

    <div class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 p-4">
      <div class="text-xs font-semibold text-gray-700 dark:text-gray-200">{$t('billing.bank')}</div>
      <div class="mt-1 text-sm font-extrabold text-gray-900 dark:text-white">
        {order.bank.name}
      </div>
      <div class="text-xs text-gray-500 dark:text-gray-400">
        {order.bank.code}
      </div>
    </div>

    <div
      class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 p-4 flex flex-col justify-between gap-3"
    >
      <div class="text-xs text-gray-600 dark:text-gray-300">
        {$t('billing.bank_transfer_hint')}
      </div>

      <button
        type="button"
        class="w-full rounded-2xl bg-primary px-4 py-2.5 text-white font-extrabold hover:opacity-90 disabled:opacity-60"
        disabled={refreshing}
        onclick={onRefresh}
      >
        {refreshing ? $t('billing.checking') : $t('billing.check_payment_status')}
      </button>
    </div>
  </div>

  <!-- Transfer details -->
  <div class="mt-4 rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 p-4">
    <div class="grid gap-3 md:grid-cols-3">
      <div class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/10 p-4">
        <div class="text-xs text-gray-500 dark:text-gray-400">{$t('billing.account_number')}</div>
        <div class="mt-1 font-mono font-extrabold text-gray-900 dark:text-white break-all">
          {order.bank.accountNumber}
        </div>
        <button
          type="button"
          class="mt-3 inline-flex items-center gap-2 text-xs font-extrabold text-primary hover:underline"
          onclick={() => copy(order.bank.accountNumber, 'acc')}
        >
          {copiedKey === 'acc' ? `✓ ${$t('billing.copied')}` : $t('billing.copy')}
        </button>
      </div>

      <div class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/10 p-4">
        <div class="text-xs text-gray-500 dark:text-gray-400">{$t('billing.account_name')}</div>
        <div class="mt-1 font-extrabold text-gray-900 dark:text-white break-all">
          {order.bank.accountName}
        </div>
        <button
          type="button"
          class="mt-3 inline-flex items-center gap-2 text-xs font-extrabold text-primary hover:underline"
          onclick={() => copy(order.bank.accountName, 'name')}
        >
          {copiedKey === 'name' ? `✓ ${$t('billing.copied')}` : $t('billing.copy')}
        </button>
      </div>

      <div class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/10 p-4">
        <div class="text-xs text-gray-500 dark:text-gray-400">{$t('billing.transfer_note')}</div>
        <div class="mt-1 font-mono font-extrabold text-gray-900 dark:text-white break-all">
          {order.transferNote}
        </div>
        <button
          type="button"
          class="mt-3 inline-flex items-center gap-2 text-xs font-extrabold text-primary hover:underline"
          onclick={() => copy(order.transferNote, 'note')}
        >
          {copiedKey === 'note' ? `✓ ${$t('billing.copied')}` : $t('billing.copy')}
        </button>
      </div>
    </div>
  </div>

  {#if error}
    <div
      class="mt-4 rounded-2xl border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-900/40 dark:bg-red-900/20 dark:text-red-200"
    >
      {error}
    </div>
  {/if}
</div>
