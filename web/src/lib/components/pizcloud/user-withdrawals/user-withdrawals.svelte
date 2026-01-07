<script lang="ts">
  import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
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

      const res = await fetch(url.toString(), {
        credentials: 'include',
      });

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
    padding-block: 1.5rem 3rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .referral-history__back {
    margin-bottom: 0.25rem;
  }

  .referral-history__back-link {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.85rem;
    text-decoration: none;
    color: var(--immich-accent, #2563eb);
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
  }

  .referral-history__filters {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .referral-history__chip {
    border-radius: 999px;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-subtle, #f8fafc);
    padding: 0.35rem 0.9rem;
    font-size: 0.85rem;
    cursor: pointer;
  }

  .referral-history__chip--active {
    border-color: var(--immich-accent, #2563eb);
    background: rgba(37, 99, 235, 0.08);
    color: var(--immich-accent, #2563eb);
  }

  .referral-history__loading,
  .referral-history__empty,
  .referral-history__error {
    padding: 2rem 0;
    text-align: center;
    font-size: 0.95rem;
  }

  .referral-history__list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .referral-history__item {
    padding: 0.9rem 1rem;
    border-radius: 0.75rem;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-elevated, #ffffff);
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
  }

  .referral-history__item-main {
    display: flex;
    justify-content: space-between;
    gap: 0.75rem;
  }

  .referral-history__amount {
    font-size: 1rem;
    font-weight: 600;
  }

  .referral-history__meta {
    margin-top: 0.1rem;
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
    font-size: 0.8rem;
    color: var(--immich-fg-muted, #64748b);
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
    color: var(--immich-fg-muted, #64748b);
  }

  .referral-history__note {
    font-size: 0.8rem;
    color: var(--immich-fg-muted, #64748b);
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
    border: 1px solid var(--immich-accent, #2563eb);
    padding: 0.45rem 1.1rem;
    font-size: 0.9rem;
    background: transparent;
    color: var(--immich-accent, #2563eb);
    cursor: pointer;
  }

  .referral-history__btn:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .spinner {
    width: 24px;
    height: 24px;
    border-radius: 999px;
    border: 3px solid #e2e8f0;
    border-top-color: var(--immich-accent, #2563eb);
    animation: spin 0.75s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
