<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import BankTransferCheckout from '$lib/components/pizcloud/purchasing/BankTransferCheckout.svelte';
  import OrderHistory from '$lib/components/pizcloud/purchasing/OrderHistory.svelte';
  import PlanCard from '$lib/components/pizcloud/purchasing/PlanCard.svelte';
  import ShortcutsModal from '$lib/modals/ShortcutsModal.svelte';
  import type { BankCode, BillingOrder, BillingProduct } from '$lib/types/pizcloud/billing';
  import {
    cancelBillingOrder,
    createBankTransferOrder,
    getBillingOrder,
    listBillingOrders,
  } from '$lib/utils/pizcloud/billing-api';
  import { Container, IconButton, modalManager } from '@immich/ui';
  import { mdiKeyboard } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let products = $derived(data.products as BillingProduct[]);
  console.log('products', products);
  let productsById = $derived(Object.fromEntries(products.map((p) => [p.id, p])) as Record<string, BillingProduct>);

  let stage = $state<'SELECT' | 'REVIEW' | 'PAY'>('SELECT');

  let period = $state<'monthly' | 'yearly'>('monthly');
  let selectedProductId = $state<string | null>(null);

  let paymentMethod = $state<'BANK_TRANSFER' | 'MOMO' | 'APPLE_PAY_QR' | 'CARD'>('BANK_TRANSFER');
  let bankCode = $state<BankCode>('VCB');

  let creating = $state(false);
  let refreshing = $state(false);
  let cancelling = $state(false);
  let cancellingId = $state<string | null>(null);
  let error = $state<string | null>(null);

  let order = $state<BillingOrder | null>(null);

  let orders = $state<BillingOrder[]>([]);
  let loadingOrders = $state(false);

  let periodProducts = $derived(products.filter((p) => p.period === period));
  let selectedProduct = $derived(periodProducts.find((p) => p.id === selectedProductId) ?? null);

  const discount = '30';

  $effect(() => {
    if (!selectedProductId && periodProducts.length) selectedProductId = periodProducts[0]!.id;
    void loadOrdersAndResume();
  });

  // =========================
  // load order history + resume pending
  // =========================
  async function loadOrdersAndResume() {
    loadingOrders = true;
    try {
      orders = await listBillingOrders(fetch, { limit: 20 });
      if (!order) {
        const pending = orders.find((o) => o.status === 'PENDING');
        if (pending) {
          order = pending;
          stage = 'PAY';
        }
      }
    } catch (e) {
      console.warn('load orders failed', e);
    } finally {
      loadingOrders = false;
    }
  }

  // =========================
  // Continue -> REVIEW
  // =========================
  function onGoReview() {
    if (!selectedProductId) return;
    error = null;
    stage = 'REVIEW';
  }

  // =========================
  // Confirm -> create order
  // =========================
  async function onCreateOrderConfirmed() {
    if (!selectedProductId) return;
    error = null;
    creating = true;
    try {
      order = await createBankTransferOrder(fetch, { productId: selectedProductId, bankCode });
      stage = 'PAY';
      await loadOrdersAndResume();
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      creating = false;
    }
  }

  async function onCreateOrder() {
    if (!selectedProductId) return;
    error = null;
    creating = true;
    try {
      order = await createBankTransferOrder(fetch, { productId: selectedProductId, bankCode });
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      creating = false;
    }
  }

  async function onRefreshOrder() {
    if (!order) return;
    error = null;
    refreshing = true;
    try {
      order = await getBillingOrder(fetch, order.id);
      await loadOrdersAndResume();
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      refreshing = false;
    }
  }

  // cancel current order
  async function onCancelCurrentOrder() {
    if (!order) return;
    if (order.status !== 'PENDING') return;

    const ok = confirm($t('billing.cancel_order_confirm_desc'));
    if (!ok) return;

    error = null;
    cancelling = true;
    try {
      order = await cancelBillingOrder(fetch, order.id);
      await loadOrdersAndResume();
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      cancelling = false;
    }
  }

  // cancel from history list
  async function onCancelFromHistory(orderId: string) {
    const ok = confirm($t('billing.cancel_order_confirm_desc'));
    if (!ok) return;

    error = null;
    cancellingId = orderId;
    try {
      const updated = await cancelBillingOrder(fetch, orderId);
      // update local
      orders = orders.map((o) => (o.id === updated.id ? updated : o));
      if (order?.id === updated.id) order = updated;
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      cancellingId = null;
    }
  }

  function openOrder(orderId: string) {
    const found = orders.find((o) => o.id === orderId);
    if (found) {
      order = found;
      stage = 'PAY';
    }
  }

  function reset() {
    order = null;
    error = null;
    stage = 'SELECT';
  }
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
  <Container size="full" center>
    <div class="mx-auto max-w-6xl px-4 py-8">
      <div
        class="rounded-[28px] border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-immich-dark-primary/20 p-4 sm:p-6 lg:p-8 backdrop-blur"
      >
        <!-- Header -->
        <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h1 class="text-2xl sm:text-3xl font-extrabold tracking-tight text-gray-900 dark:text-white">
              {$t('billing.upgrade_storage')}
            </h1>
            <p class="mt-1 text-sm text-gray-600 dark:text-gray-300">
              {$t('billing.choose_plan_desc')}
            </p>
          </div>

          {#if order}
            <button type="button" class="text-sm font-semibold text-primary hover:underline" onclick={reset}>
              {$t('billing.choose_another_plan')}
            </button>
          {/if}
        </div>

        <!-- {#if !order}
          <div class="mt-6 grid gap-6 lg:grid-cols-[1fr_360px]">
            <div>
              <div class="flex items-center justify-between gap-3">
                <div class="text-sm font-semibold text-gray-900 dark:text-white">
                  Kỳ thanh toán
                </div>

                <div
                  class="inline-flex rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/30 p-1"
                >
                  <button
                    type="button"
                    class={[
                      'px-4 py-2 rounded-xl text-sm font-bold transition',
                      period === 'monthly'
                        ? 'bg-primary text-white shadow-sm'
                        : 'text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800/60',
                    ].join(' ')}
                    onclick={() => (period = 'monthly')}
                  >
                    {$t('billing.billing_monthly')}
                  </button>

                  <button
                    type="button"
                    class={[
                      'px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2',
                      period === 'yearly'
                        ? 'bg-primary text-white shadow-sm'
                        : 'text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800/60',
                    ].join(' ')}
                    onclick={() => (period = 'yearly')}
                  >
                    {$t('billing.billing_yearly')}
                    <span
                      class="rounded-full bg-emerald-100 text-emerald-700 px-2 py-0.5 text-[11px] font-extrabold dark:bg-emerald-900/30 dark:text-emerald-200"
                    >
                      Save 20%
                    </span>
                  </button>
                </div>
              </div>
              <div class="flex items-center justify-between gap-3">
                {#if discount}
                  <div
                    class="mt-3 rounded-2xl border border-emerald-100 dark:border-emerald-900/40 bg-emerald-50 dark:bg-emerald-900/20 px-3 py-2 text-xs text-emerald-700 dark:text-emerald-200"
                  >
                    {$t('referral.you_are_receiving_discount_on_this_plan')}
                  </div>
                {/if}
              </div>

              <div class="mt-4 grid gap-4 sm:grid-cols-1 xl:grid-cols-2">
                {#each periodProducts as p (p.id)}
                  <PlanCard
                    product={p}
                    selected={p.id === selectedProductId}
                    onSelect={(id) => (selectedProductId = id)}
                  />
                {/each}
              </div>

              <div class="mt-7">
                <div class="flex items-center justify-between">
                  <div class="text-sm font-semibold text-gray-900 dark:text-white">
                    {$t('billing.payment_method')}
                  </div>
                  <div class="text-xs text-gray-500 dark:text-gray-400">
                    {$t('billing.coming_soon')}
                  </div>
                </div>

                <div class="mt-3 grid gap-3 md:grid-cols-2">
                  <div
                    role="button"
                    tabindex="0"
                    aria-pressed={paymentMethod === 'BANK_TRANSFER'}
                    class={[
                      'rounded-3xl border p-4 text-left transition cursor-pointer',
                      'bg-white/60 dark:bg-immich-dark-primary/15 backdrop-blur',
                      paymentMethod === 'BANK_TRANSFER'
                        ? 'border-primary ring-2 ring-primary/25 shadow-sm'
                        : 'border-gray-200 dark:border-gray-700 hover:border-primary/40',
                    ].join(' ')}
                    onclick={() => (paymentMethod = 'BANK_TRANSFER')}
                    onkeydown={(e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        paymentMethod = 'BANK_TRANSFER';
                      }
                    }}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="font-extrabold text-gray-900 dark:text-white">
                          {$t('billing.bank_transfer')}
                        </div>
                        <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">
                          {$t('billing.bank_transfer_desc')}
                        </div>
                      </div>

                      <div
                        class={[
                          'mt-1 h-5 w-5 rounded-full border flex items-center justify-center',
                          paymentMethod === 'BANK_TRANSFER' ? 'border-primary' : 'border-gray-300 dark:border-gray-600',
                        ].join(' ')}
                      >
                        {#if paymentMethod === 'BANK_TRANSFER'}
                          <div class="h-2.5 w-2.5 rounded-full bg-primary"></div>
                        {/if}
                      </div>
                    </div>

                    <div class="mt-4 flex flex-wrap gap-2">
                      <button
                        type="button"
                        class={[
                          'rounded-2xl border px-3 py-2 text-sm font-bold transition',
                          bankCode === 'VCB'
                            ? 'border-primary bg-primary/10 text-gray-900 dark:text-white'
                            : 'border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800/40',
                        ].join(' ')}
                        onclick={(e) => {
                          e.stopPropagation();
                          paymentMethod = 'BANK_TRANSFER';
                          bankCode = 'VCB';
                        }}
                      >
                        Vietcombank
                      </button>

                      <button
                        type="button"
                        class={[
                          'rounded-2xl border px-3 py-2 text-sm font-bold transition',
                          bankCode === 'ACB'
                            ? 'border-primary bg-primary/10 text-gray-900 dark:text-white'
                            : 'border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800/40',
                        ].join(' ')}
                        onclick={(e) => {
                          e.stopPropagation();
                          paymentMethod = 'BANK_TRANSFER';
                          bankCode = 'ACB';
                        }}
                      >
                        ACB
                      </button>
                    </div>

                    <div
                      class="mt-3 rounded-2xl border border-emerald-100 dark:border-emerald-900/40 bg-emerald-50 dark:bg-emerald-900/20 px-3 py-2 text-xs text-emerald-700 dark:text-emerald-200"
                    >
                      {$t('billing.bank_transfer_hint')}
                    </div>
                  </div>

                  <div
                    class="rounded-3xl border border-gray-200 dark:border-gray-700 p-4 bg-gray-50/80 dark:bg-gray-900/20 opacity-80"
                  >
                    <div class="font-extrabold text-gray-900 dark:text-white">MoMo</div>
                    <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.coming_soon')}</div>
                  </div>

                  <div
                    class="rounded-3xl border border-gray-200 dark:border-gray-700 p-4 bg-gray-50/80 dark:bg-gray-900/20 opacity-80"
                  >
                    <div class="font-extrabold text-gray-900 dark:text-white">Apple Pay - QR</div>
                    <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.coming_soon')}</div>
                  </div>

                  <div
                    class="rounded-3xl border border-gray-200 dark:border-gray-700 p-4 bg-gray-50/80 dark:bg-gray-900/20 opacity-80"
                  >
                    <div class="font-extrabold text-gray-900 dark:text-white">
                      {$t('billing.international_card')}
                    </div>
                    <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.coming_soon')}</div>
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

            <aside
              class="h-fit rounded-3xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-immich-dark-primary/20 p-5 sm:p-6 lg:sticky lg:top-6 backdrop-blur"
            >
              <div class="text-sm font-extrabold text-gray-900 dark:text-white">Summary</div>

              <div
                class="mt-4 rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 p-4"
              >
                {#if selectedProduct}
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <div class="text-base font-extrabold text-gray-900 dark:text-white">
                        {selectedProduct.planCode}
                      </div>
                      <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">
                        {selectedProduct.storageLimitGb} GB
                        <span class="mx-2 opacity-60">•</span>
                        <span
                          >{period === 'monthly' ? $t('billing.billing_monthly') : $t('billing.billing_yearly')}</span
                        >
                      </div>
                    </div>

                    {#if typeof selectedProduct.priceUsd === 'number'}
                      <div class="text-right">
                        <div class="text-lg font-extrabold text-gray-900 dark:text-white">
                          {selectedProduct.priceUsd} VND
                        </div>
                        <div class="text-xs text-gray-500 dark:text-gray-400">
                          {selectedProduct.period === 'monthly' ? $t('billing.per_month') : $t('billing.per_year')}
                        </div>
                      </div>
                    {/if}
                  </div>
                {:else}
                  <div class="text-sm text-gray-600 dark:text-gray-300">Chọn gói để tiếp tục.</div>
                {/if}

                <div class="mt-4 border-t border-gray-200 dark:border-gray-700 pt-4 space-y-2 text-sm">
                  <div class="flex items-center justify-between">
                    <span class="text-gray-600 dark:text-gray-300">{$t('billing.payment_method')}</span>
                    <span class="font-bold text-gray-900 dark:text-white">
                      {paymentMethod === 'BANK_TRANSFER' ? $t('billing.bank_transfer') : '-'}
                    </span>
                  </div>

                  {#if paymentMethod === 'BANK_TRANSFER'}
                    <div class="flex items-center justify-between">
                      <span class="text-gray-600 dark:text-gray-300">{$t('billing.bank')}</span>
                      <span class="font-bold text-gray-900 dark:text-white">{bankCode || '-'}</span>
                    </div>
                  {/if}
                </div>
              </div>

              <button
                type="button"
                class="mt-4 w-full rounded-2xl bg-primary px-5 py-3 text-white font-extrabold hover:opacity-90 disabled:opacity-60"
                disabled={!selectedProductId || paymentMethod !== 'BANK_TRANSFER' || creating}
                onclick={onCreateOrder}
              >
                {creating ? $t('billing.creating_order') : $t('billing.continue')}
              </button>

              <div class="mt-3 text-xs text-gray-500 dark:text-gray-400 leading-relaxed">
                {$t('billing.bank_transfer_hint')}
              </div>
            </aside>
          </div>
        {:else}
          <div class="mt-6">
            <BankTransferCheckout {order} onRefresh={onRefreshOrder} {refreshing} {error} />

            {#if order.status === 'PAID'}
              <div
                class="mt-4 rounded-3xl border border-green-200 bg-green-50 p-4 text-green-800 dark:border-green-900/40 dark:bg-green-900/20 dark:text-green-200"
              >
                <div class="font-extrabold">{$t('billing.payment_success')}</div>
                <div class="text-sm mt-1">{$t('billing.payment_success_desc')}</div>
              </div>
            {/if}
          </div>
        {/if} -->

        {#if stage === 'SELECT' && !order}
          <div class="mt-6 grid gap-6 lg:grid-cols-[1fr_360px]">
            <!-- LEFT -->
            <div>
              <!-- Period switch -->
              <div class="flex items-center justify-between gap-3">
                <div class="text-sm font-semibold text-gray-900 dark:text-white">
                  {$t('billing.billing_period')}
                </div>

                <div
                  class="inline-flex rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/30 p-1"
                >
                  <button
                    type="button"
                    class={[
                      'px-4 py-2 rounded-xl text-sm font-bold transition',
                      period === 'monthly'
                        ? 'bg-primary text-white shadow-sm'
                        : 'text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800/60',
                    ].join(' ')}
                    onclick={() => (period = 'monthly')}
                  >
                    {$t('billing.billing_monthly')}
                  </button>

                  <button
                    type="button"
                    class={[
                      'px-4 py-2 rounded-xl text-sm font-bold transition flex items-center gap-2',
                      period === 'yearly'
                        ? 'bg-primary text-white shadow-sm'
                        : 'text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800/60',
                    ].join(' ')}
                    onclick={() => (period = 'yearly')}
                  >
                    {$t('billing.billing_yearly')}
                    <span
                      class="rounded-full bg-emerald-100 text-emerald-700 px-2 py-0.5 text-[11px] font-extrabold dark:bg-emerald-900/30 dark:text-emerald-200"
                    >
                      {$t('billing.save_percent', { values: { percent: 20 } })}
                    </span>
                  </button>
                </div>
              </div>

              {#if discount}
                <div
                  class="mt-3 rounded-2xl border border-emerald-100 dark:border-emerald-900/40 bg-emerald-50 dark:bg-emerald-900/20 px-3 py-2 text-xs text-emerald-700 dark:text-emerald-200"
                >
                  {$t('referral.you_are_receiving_discount_on_this_plan')}
                </div>
              {/if}

              <!-- Plans -->
              <div class="mt-4 grid gap-4 sm:grid-cols-1 xl:grid-cols-2">
                {#each periodProducts as p (p.id)}
                  <PlanCard
                    product={p}
                    selected={p.id === selectedProductId}
                    onSelect={(id) => (selectedProductId = id)}
                  />
                {/each}
              </div>

              <!-- Payment methods -->
              <div class="mt-7">
                <div class="flex items-center justify-between">
                  <div class="text-sm font-semibold text-gray-900 dark:text-white">
                    {$t('billing.payment_method')}
                  </div>
                  <div class="text-xs text-gray-500 dark:text-gray-400">
                    {$t('billing.coming_soon')}
                  </div>
                </div>

                <div class="mt-3 grid gap-3 md:grid-cols-2">
                  <!-- BANK TRANSFER -->
                  <div
                    role="button"
                    tabindex="0"
                    aria-pressed={paymentMethod === 'BANK_TRANSFER'}
                    class={[
                      'rounded-3xl border p-4 text-left transition cursor-pointer',
                      'bg-white/60 dark:bg-immich-dark-primary/15 backdrop-blur',
                      paymentMethod === 'BANK_TRANSFER'
                        ? 'border-primary ring-2 ring-primary/25 shadow-sm'
                        : 'border-gray-200 dark:border-gray-700 hover:border-primary/40',
                    ].join(' ')}
                    onclick={() => (paymentMethod = 'BANK_TRANSFER')}
                    onkeydown={(e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        paymentMethod = 'BANK_TRANSFER';
                      }
                    }}
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <div class="font-extrabold text-gray-900 dark:text-white">
                          {$t('billing.bank_transfer')}
                        </div>
                        <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">
                          {$t('billing.bank_transfer_desc')}
                        </div>
                      </div>

                      <div
                        class={[
                          'mt-1 h-5 w-5 rounded-full border flex items-center justify-center',
                          paymentMethod === 'BANK_TRANSFER' ? 'border-primary' : 'border-gray-300 dark:border-gray-600',
                        ].join(' ')}
                      >
                        {#if paymentMethod === 'BANK_TRANSFER'}
                          <div class="h-2.5 w-2.5 rounded-full bg-primary"></div>
                        {/if}
                      </div>
                    </div>

                    <div class="mt-4 flex flex-wrap gap-2">
                      <button
                        type="button"
                        class={[
                          'rounded-2xl border px-3 py-2 text-sm font-bold transition',
                          bankCode === 'VCB'
                            ? 'border-primary bg-primary/10 text-gray-900 dark:text-white'
                            : 'border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800/40',
                        ].join(' ')}
                        onclick={(e) => {
                          e.stopPropagation();
                          paymentMethod = 'BANK_TRANSFER';
                          bankCode = 'VCB';
                        }}
                      >
                        Vietcombank
                      </button>

                      <button
                        type="button"
                        class={[
                          'rounded-2xl border px-3 py-2 text-sm font-bold transition',
                          bankCode === 'ACB'
                            ? 'border-primary bg-primary/10 text-gray-900 dark:text-white'
                            : 'border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-800/40',
                        ].join(' ')}
                        onclick={(e) => {
                          e.stopPropagation();
                          paymentMethod = 'BANK_TRANSFER';
                          bankCode = 'ACB';
                        }}
                      >
                        ACB
                      </button>
                    </div>

                    <div
                      class="mt-3 rounded-2xl border border-emerald-100 dark:border-emerald-900/40 bg-emerald-50 dark:bg-emerald-900/20 px-3 py-2 text-xs text-emerald-700 dark:text-emerald-200"
                    >
                      {$t('billing.bank_transfer_hint')}
                    </div>
                  </div>

                  <!-- Coming soon placeholders -->
                  <div
                    class="rounded-3xl border border-gray-200 dark:border-gray-700 p-4 bg-gray-50/80 dark:bg-gray-900/20 opacity-80"
                  >
                    <div class="font-extrabold text-gray-900 dark:text-white">MoMo</div>
                    <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.coming_soon')}</div>
                  </div>

                  <div
                    class="rounded-3xl border border-gray-200 dark:border-gray-700 p-4 bg-gray-50/80 dark:bg-gray-900/20 opacity-80"
                  >
                    <div class="font-extrabold text-gray-900 dark:text-white">Apple Pay - QR</div>
                    <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.coming_soon')}</div>
                  </div>

                  <div
                    class="rounded-3xl border border-gray-200 dark:border-gray-700 p-4 bg-gray-50/80 dark:bg-gray-900/20 opacity-80"
                  >
                    <div class="font-extrabold text-gray-900 dark:text-white">{$t('billing.international_card')}</div>
                    <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.coming_soon')}</div>
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

              <!-- history -->
              <OrderHistory {orders} {productsById} onOpen={openOrder} onCancel={onCancelFromHistory} {cancellingId} />
            </div>

            <!-- Summary + CTA -->
            <aside
              class="h-fit rounded-3xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-immich-dark-primary/20 p-5 sm:p-6 lg:sticky lg:top-6 backdrop-blur"
            >
              <div class="text-sm font-extrabold text-gray-900 dark:text-white">{$t('billing.summary')}</div>

              <div
                class="mt-4 rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 p-4"
              >
                {#if selectedProduct}
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <div class="text-base font-extrabold text-gray-900 dark:text-white">
                        {selectedProduct.planCode}
                      </div>
                      <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">
                        {selectedProduct.storageLimitGb} GB
                        <span class="mx-2 opacity-60">•</span>
                        <span
                          >{period === 'monthly' ? $t('billing.billing_monthly') : $t('billing.billing_yearly')}</span
                        >
                      </div>
                    </div>

                    <div class="text-right">
                      <div class="text-lg font-extrabold text-gray-900 dark:text-white">
                        {selectedProduct.priceVnd} VND
                      </div>
                      <div class="text-xs text-gray-500 dark:text-gray-400">
                        {selectedProduct.period === 'monthly' ? $t('billing.per_month') : $t('billing.per_year')}
                      </div>
                    </div>
                  </div>
                {:else}
                  <div class="text-sm text-gray-600 dark:text-gray-300">{$t('billing.select_plan_to_continue')}</div>
                {/if}

                <div class="mt-4 border-t border-gray-200 dark:border-gray-700 pt-4 space-y-2 text-sm">
                  <div class="flex items-center justify-between">
                    <span class="text-gray-600 dark:text-gray-300">{$t('billing.payment_method')}</span>
                    <span class="font-bold text-gray-900 dark:text-white">
                      {paymentMethod === 'BANK_TRANSFER' ? $t('billing.bank_transfer') : '-'}
                    </span>
                  </div>

                  {#if paymentMethod === 'BANK_TRANSFER'}
                    <div class="flex items-center justify-between">
                      <span class="text-gray-600 dark:text-gray-300">{$t('billing.bank')}</span>
                      <span class="font-bold text-gray-900 dark:text-white">{bankCode || '-'}</span>
                    </div>
                  {/if}
                </div>
              </div>

              <!-- Continue -> REVIEW -->
              <button
                type="button"
                class="mt-4 w-full rounded-2xl bg-primary px-5 py-3 text-white font-extrabold hover:opacity-90 disabled:opacity-60"
                disabled={!selectedProductId || paymentMethod !== 'BANK_TRANSFER' || creating}
                onclick={onGoReview}
              >
                {$t('billing.continue')}
              </button>

              <div class="mt-3 text-xs text-gray-500 dark:text-gray-400 leading-relaxed">
                {$t('billing.bank_transfer_hint')}
              </div>
            </aside>
          </div>
        {:else if stage === 'REVIEW' && !order}
          <div
            class="mt-6 rounded-3xl border border-gray-200 dark:border-gray-700 bg-white/60 dark:bg-gray-900/15 p-5 sm:p-6"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <div class="text-lg font-extrabold text-gray-900 dark:text-white">{$t('billing.review_order')}</div>
                <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.review_order_desc')}</div>
              </div>

              <button
                type="button"
                class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-gray-900/20 px-4 py-2 text-sm font-extrabold text-gray-900 dark:text-white hover:bg-gray-50 dark:hover:bg-gray-800/30"
                onclick={() => (stage = 'SELECT')}
              >
                {$t('billing.back')}
              </button>
            </div>

            <div class="mt-5 grid gap-4 lg:grid-cols-3">
              <div class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-gray-900/20 p-4">
                <div class="text-xs text-gray-500 dark:text-gray-400">{$t('billing.plan')}</div>
                <div class="mt-1 font-extrabold text-gray-900 dark:text-white">
                  {selectedProduct ? `${selectedProduct.planCode} • ${selectedProduct.storageLimitGb}GB` : '-'}
                </div>
                <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">
                  {period === 'monthly' ? $t('billing.billing_monthly') : $t('billing.billing_yearly')}
                </div>
              </div>

              <div class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-gray-900/20 p-4">
                <div class="text-xs text-gray-500 dark:text-gray-400">{$t('billing.payment_method')}</div>
                <div class="mt-1 font-extrabold text-gray-900 dark:text-white">{$t('billing.bank_transfer')}</div>
                <div class="mt-1 text-sm text-gray-600 dark:text-gray-300">{$t('billing.bank')}: {bankCode}</div>
              </div>

              <div class="rounded-2xl border border-primary/20 bg-primary/5 dark:bg-primary/10 p-4">
                <div class="text-xs text-gray-600 dark:text-gray-300">{$t('billing.amount')}</div>
                <div class="mt-1 text-2xl font-extrabold text-gray-900 dark:text-white">
                  {selectedProduct ? `${selectedProduct.priceVnd} VND` : '-'}
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

            <div class="mt-5 flex flex-col sm:flex-row gap-3 sm:justify-end">
              <button
                type="button"
                class="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white/70 dark:bg-gray-900/20 px-5 py-3 text-sm font-extrabold text-gray-900 dark:text-white hover:bg-gray-50 dark:hover:bg-gray-800/30"
                onclick={() => (stage = 'SELECT')}
              >
                {$t('billing.back')}
              </button>

              <button
                type="button"
                class="rounded-2xl bg-primary px-6 py-3 text-white font-extrabold hover:opacity-90 disabled:opacity-60"
                disabled={!selectedProductId || creating}
                onclick={onCreateOrderConfirmed}
              >
                {creating ? $t('billing.creating_order') : $t('billing.confirm_and_create_order')}
              </button>
            </div>
          </div>
        {:else}
          <div class="mt-6">
            {#if order}
              <BankTransferCheckout
                {order}
                onRefresh={onRefreshOrder}
                onCancel={onCancelCurrentOrder}
                {refreshing}
                {cancelling}
                {error}
              />

              {#if order.status === 'PAID'}
                <div
                  class="mt-4 rounded-3xl border border-green-200 bg-green-50 p-4 text-green-800 dark:border-green-900/40 dark:bg-green-900/20 dark:text-green-200"
                >
                  <div class="font-extrabold">{$t('billing.payment_success')}</div>
                  <div class="text-sm mt-1">{$t('billing.payment_success_desc')}</div>
                </div>
              {/if}
            {/if}

            <OrderHistory {orders} {productsById} onOpen={openOrder} onCancel={onCancelFromHistory} {cancellingId} />
          </div>
        {/if}
      </div>
    </div>
  </Container>
</UserPageLayout>
