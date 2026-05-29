<script lang="ts">
  import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
  import { fetchWithClientTelemetry } from '$lib/telemetry/client-telemetry';
  import { getPizcloudApiBaseUrl } from '$lib/utils/api-base';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  type ReferralWithdrawStatus = 'pending' | 'approved' | 'rejected' | 'paid';

  interface ReferralWithdrawalItem {
    _id: string;
    amount: number;
    currency: string;
    status: ReferralWithdrawStatus;
    method: 'bank' | 'paypal';
    note?: string | null;
    adminNote?: string | null;
    createdAt?: string | null;
    processedAt?: string | null;
  }

  interface ReferralWithdrawalListResponse {
    pagination: {
      page: number;
      limit: number;
      total: number;
    };
    items: ReferralWithdrawalItem[];
  }

  interface Props {
    userEmail: string;
  }

  let { userEmail }: Props = $props();

  let loading = $state(true);
  let loadingMore = $state(false);
  let error = $state('');

  let items = $state<ReferralWithdrawalItem[]>([]);
  let page = $state(1);
  let limit = $state(10);
  let total = $state(0);
  let selectedStatus = $state<'all' | ReferralWithdrawStatus>('all');

  const baseUrl = (getPizcloudApiBaseUrl() || PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');

  function canLoadMore() {
    return items.length < total;
  }

  function formatDateTime(value?: string | null) {
    if (!value) return '';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return value;
    return d.toLocaleString();
  }

  function statusLabel(status: ReferralWithdrawStatus) {
    switch (status) {
      case 'pending':
        return $t('referral.withdraw_status_pending');
      case 'approved':
        return $t('referral.withdraw_status_approved');
      case 'rejected':
        return $t('referral.withdraw_status_rejected');
      case 'paid':
        return $t('referral.withdraw_status_paid');
    }
  }

  async function load(reset = false) {
    if (!userEmail) {
      error = $t('referral.withdraw_missing_email');
      loading = false;
      return;
    }

    if (reset) {
      page = 1;
      items = [];
    }

    if (page === 1) {
      loading = true;
      error = '';
    } else {
      loadingMore = true;
    }

    try {
      const url = new URL(`${baseUrl}/referral/withdrawals`, globalThis.location.origin);
      // url.searchParams.set('email', userEmail);
      url.searchParams.set('page', String(page));
      url.searchParams.set('limit', String(limit));
      if (selectedStatus !== 'all') {
        url.searchParams.set('status', selectedStatus);
      }

      const res = await fetchWithClientTelemetry(
        url.toString(),
        {
          credentials: 'include',
        },
        { eventName: 'referral.withdrawals.list' },
      );

      if (!res.ok) {
        error = $t('referral.withdraw_history_load_error');
        return;
      }

      const data: ReferralWithdrawalListResponse = await res.json();
      total = data.pagination.total;
      limit = data.pagination.limit;

      if (page === 1) {
        items = data.items ?? [];
      } else {
        items = [...items, ...(data.items ?? [])];
      }
    } catch (e) {
      console.error('Error loading withdrawal history', e);
      error = $t('referral.withdraw_history_load_error');
    } finally {
      loading = false;
      loadingMore = false;
    }
  }

  function changeStatus(status: 'all' | ReferralWithdrawStatus) {
    if (selectedStatus === status) return;
    selectedStatus = status;
    page = 1;
    load(true);
  }

  function loadMore() {
    if (!canLoadMore() || loadingMore) return;
    page = page + 1;
    load(false);
  }

  onMount(() => {
    load(true);
  });
</script>

<section class="referral-history">
  <div class="referral-history__back">
    <a href="/pizcloud/referral" class="referral-history__back-link">
      <span class="referral-history__back-icon">←</span>
      <span>{$t('back')}</span>
    </a>
  </div>

  <header class="referral-history__header">
    <h1 class="referral-history__title">
      {$t('referral.withdraw_history_title')}
    </h1>
  </header>

  <div class="referral-history__filters">
    <button
      type="button"
      class="referral-history__chip"
      class:referral-history__chip--active={selectedStatus === 'all'}
      onclick={() => changeStatus('all')}
    >
      {$t('all')}
    </button>
    <button
      type="button"
      class="referral-history__chip"
      class:referral-history__chip--active={selectedStatus === 'pending'}
      onclick={() => changeStatus('pending')}
    >
      {$t('referral.withdraw_status_pending')}
    </button>
    <button
      type="button"
      class="referral-history__chip"
      class:referral-history__chip--active={selectedStatus === 'approved'}
      onclick={() => changeStatus('approved')}
    >
      {$t('referral.withdraw_status_approved')}
    </button>
    <button
      type="button"
      class="referral-history__chip"
      class:referral-history__chip--active={selectedStatus === 'rejected'}
      onclick={() => changeStatus('rejected')}
    >
      {$t('referral.withdraw_status_rejected')}
    </button>
    <button
      type="button"
      class="referral-history__chip"
      class:referral-history__chip--active={selectedStatus === 'paid'}
      onclick={() => changeStatus('paid')}
    >
      {$t('referral.withdraw_status_paid')}
    </button>
  </div>

  {#if loading}
    <div class="referral-history__loading">
      <div class="spinner"></div>
    </div>
  {:else if error}
    <div class="referral-history__error">
      <p>{error}</p>
      <button type="button" class="referral-history__btn" onclick={() => load(true)}>
        {$t('retry')}
      </button>
    </div>
  {:else if items.length === 0}
    <div class="referral-history__empty">
      <p>{$t('referral.withdraw_history_empty')}</p>
    </div>
  {:else}
    <div class="referral-history__list">
      {#each items as item (item._id)}
        <article class="referral-history__item">
          <div class="referral-history__item-main">
            <div>
              <div class="referral-history__amount">
                {item.amount.toFixed(2)}
                {item.currency}
              </div>
              <div class="referral-history__meta">
                {#if item.createdAt}
                  <span>
                    {$t('referral.withdraw_created_at', {
                      values: { date: formatDateTime(item.createdAt) },
                    })}
                  </span>
                {/if}
                {#if item.processedAt}
                  <span>
                    {$t('referral.withdraw_processed_at', {
                      values: { date: formatDateTime(item.processedAt) },
                    })}
                  </span>
                {/if}
              </div>
            </div>
            <div class="referral-history__status-block">
              <span class="referral-history__status" data-status={item.status}>
                {statusLabel(item.status)}
              </span>
              <span class="referral-history__method">
                {item.method.toUpperCase()}
              </span>
            </div>
          </div>

          {#if item.note}
            <div class="referral-history__note">
              <span class="referral-history__note-label">
                {$t('referral.withdraw_user_note')}:
              </span>
              <span>{item.note}</span>
            </div>
          {/if}

          {#if item.adminNote}
            <div class="referral-history__note referral-history__note--admin">
              <span class="referral-history__note-label">
                {$t('referral.withdraw_admin_note')}:
              </span>
              <span>{item.adminNote}</span>
            </div>
          {/if}
        </article>
      {/each}
    </div>

    {#if canLoadMore()}
      <div class="referral-history__load-more">
        <button type="button" class="referral-history__btn" onclick={loadMore} disabled={loadingMore}>
          {#if loadingMore}
            {$t('referral.withdraw_history_loading_more')}
          {:else}
            {$t('referral.withdraw_history_load_more')}
          {/if}
        </button>
      </div>
    {/if}
  {/if}
</section>

<style>
  .referral-history {
    --rw-bg: var(--pizcloud-bg-elevated, #ffffff);
    --rw-bg-soft: var(--pizcloud-bg-subtle, #f8fafc);
    --rw-bg-muted: var(--pizcloud-bg-muted, #f1f5f9);
    --rw-border: var(--pizcloud-border-subtle, #e2e8f0);
    --rw-text: var(--pizcloud-fg, inherit);
    --rw-text-muted: var(--pizcloud-fg-muted, #64748b);
    --rw-accent: var(--pizcloud-accent, #2563eb);
    --rw-accent-strong: var(--pizcloud-accent-strong, #1d4ed8);
    padding-block: 1.5rem 3rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
    color: var(--rw-text);
  }

  /* Legacy style reference before unified light/dark tokens:
     - chips/buttons used direct var(--pizcloud-accent) and transparent button bg
     - cards/status blocks only tuned for light surfaces */

  .referral-history__back {
    margin-bottom: 0.25rem;
  }

  .referral-history__back-link {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.85rem;
    text-decoration: none;
    color: var(--rw-accent);
  }

  .referral-history__back-link:hover {
    text-decoration: underline;
  }

  .referral-history__back-icon {
    font-size: 1rem;
    line-height: 1;
  }

  .referral-history__header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .referral-history__title {
    margin: 0;
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--rw-text);
  }

  .referral-history__filters {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .referral-history__chip {
    border-radius: 999px;
    border: 1px solid var(--rw-border);
    background: var(--rw-bg-soft);
    color: var(--rw-text);
    padding: 0.35rem 0.9rem;
    font-size: 0.85rem;
    cursor: pointer;
    transition:
      background-color 0.15s ease,
      border-color 0.15s ease,
      color 0.15s ease;
  }

  .referral-history__chip--active {
    border-color: var(--rw-accent);
    background: rgba(37, 99, 235, 0.08);
    color: var(--rw-accent);
  }

  .referral-history__loading,
  .referral-history__empty,
  .referral-history__error {
    padding: 2rem 0;
    text-align: center;
    font-size: 0.95rem;
    color: var(--rw-text-muted);
  }

  .referral-history__list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .referral-history__item {
    padding: 0.9rem 1rem;
    border-radius: 0.75rem;
    border: 1px solid var(--rw-border);
    background: var(--rw-bg);
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
    box-shadow: 0 8px 22px rgba(15, 23, 42, 0.06);
  }

  .referral-history__item-main {
    display: flex;
    justify-content: space-between;
    gap: 0.75rem;
  }

  .referral-history__amount {
    font-size: 1rem;
    font-weight: 600;
    color: var(--rw-text);
  }

  .referral-history__meta {
    margin-top: 0.1rem;
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
    font-size: 0.8rem;
    color: var(--rw-text-muted);
  }

  .referral-history__status-block {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 0.25rem;
    font-size: 0.8rem;
  }

  .referral-history__status {
    padding: 0.15rem 0.6rem;
    border-radius: 999px;
    border: 1px solid transparent;
    font-size: 0.75rem;
    font-weight: 500;
  }

  .referral-history__status[data-status='pending'] {
    background: #fffbeb;
    border-color: #fbbf24;
    color: #92400e;
  }

  .referral-history__status[data-status='approved'] {
    background: #eff6ff;
    border-color: #60a5fa;
    color: #1d4ed8;
  }

  .referral-history__status[data-status='rejected'] {
    background: #fef2f2;
    border-color: #fca5a5;
    color: #b91c1c;
  }

  .referral-history__status[data-status='paid'] {
    background: #ecfdf5;
    border-color: #6ee7b7;
    color: #15803d;
  }

  .referral-history__method {
    font-size: 0.75rem;
    color: var(--rw-text-muted);
  }

  .referral-history__note {
    font-size: 0.8rem;
    color: var(--rw-text-muted);
  }

  .referral-history__note--admin {
    font-style: italic;
  }

  .referral-history__note-label {
    font-weight: 500;
    margin-right: 0.25rem;
  }

  .referral-history__load-more {
    margin-top: 0.5rem;
    display: flex;
    justify-content: center;
  }

  .referral-history__btn {
    border-radius: 999px;
    border: 1px solid var(--rw-accent);
    padding: 0.45rem 1.1rem;
    font-size: 0.9rem;
    background: var(--rw-bg-soft);
    color: var(--rw-accent);
    cursor: pointer;
    transition:
      background-color 0.15s ease,
      border-color 0.15s ease,
      color 0.15s ease;
  }

  .referral-history__btn:hover:not(:disabled) {
    background: var(--rw-bg-muted);
    border-color: var(--rw-accent-strong);
    color: var(--rw-accent-strong);
  }

  .referral-history__btn:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .spinner {
    width: 24px;
    height: 24px;
    border-radius: 999px;
    border: 3px solid var(--rw-border);
    border-top-color: var(--rw-accent);
    animation: spin 0.75s linear infinite;
  }

  :global(.dark) .referral-history {
    --rw-bg: var(--pizcloud-dark-surface, rgb(33 33 33));
    --rw-bg-soft: var(--pizcloud-dark-bg, rgb(10 10 10));
    --rw-bg-muted: var(--pizcloud-dark-muted, rgba(148, 163, 184, 0.12));
    --rw-border: var(--pizcloud-dark-border, rgba(148, 163, 184, 0.22));
    --rw-text: var(--pizcloud-dark-fg, rgb(229 231 235));
    --rw-text-muted: var(--pizcloud-dark-fg-muted, rgba(229, 231, 235, 0.72));
    --rw-accent: var(--pizcloud-dark-primary, rgb(172 203 250));
    --rw-accent-strong: var(--pizcloud-dark-primary-strong, rgba(172, 203, 250, 0.92));
  }

  :global(.dark) .referral-history .referral-history__item {
    box-shadow: var(--pizcloud-dark-shadow, 0 10px 22px rgba(0, 0, 0, 0.42));
  }

  :global(.dark) .referral-history .referral-history__chip--active {
    background: rgba(172, 203, 250, 0.18);
    border-color: rgba(172, 203, 250, 0.34);
    color: rgb(191 219 254);
  }

  :global(.dark) .referral-history .referral-history__status[data-status='pending'] {
    background: rgba(245, 158, 11, 0.26);
    border-color: rgba(245, 158, 11, 0.5);
    color: rgb(252 211 77);
  }

  :global(.dark) .referral-history .referral-history__status[data-status='approved'] {
    background: rgba(147, 197, 253, 0.24);
    border-color: rgba(147, 197, 253, 0.5);
    color: rgb(191 219 254);
  }

  :global(.dark) .referral-history .referral-history__status[data-status='rejected'] {
    background: rgba(248, 113, 113, 0.22);
    border-color: rgba(248, 113, 113, 0.48);
    color: rgb(252 165 165);
  }

  :global(.dark) .referral-history .referral-history__status[data-status='paid'] {
    background: rgba(34, 197, 94, 0.24);
    border-color: rgba(34, 197, 94, 0.5);
    color: rgb(134 239 172);
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
