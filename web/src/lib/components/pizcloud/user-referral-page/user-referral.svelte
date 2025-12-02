<script lang="ts">
  import { t } from 'svelte-i18n';

  interface MonthlyStat {
    month: string;
    commission: number;
    activeUsers: number;
  }

  interface Props {
    referralCode?: string;
    totalReferredUsers?: number;
    totalCommission?: number;
    monthlyStats?: MonthlyStat[];
    currency?: string;

    keys?: unknown;
    sessions?: unknown;
  }

  let {
    referralCode = 'ABC123DEF',
    totalReferredUsers = 0,
    totalCommission = 0,
    monthlyStats = [],
    currency = 'VND',
    keys,
    sessions,
  }: Props = $props();

  let copyMessage = $state('');
  let shareMessage = $state('');

  function isEmptyState() {
    return totalReferredUsers === 0 && totalCommission === 0 && monthlyStats.length === 0;
  }

  function formatMonth(month: string): string {
    const [year, monthStr] = month.split('-');
    if (!year || !monthStr) {
      return month;
    }

    const m = monthStr.padStart(2, '0');
    return `${m}/${year}`;
  }

  function formatCurrency(amount: number): string {
    if (!Number.isFinite(amount)) {
      return '0';
    }

    try {
      return new Intl.NumberFormat('vi-VN', {
        style: 'currency',
        currency,
      }).format(amount);
    } catch {
      return `${amount.toLocaleString('vi-VN')} ${currency}`;
    }
  }

  async function handleCopy() {
    copyMessage = '';
    shareMessage = '';

    try {
      await navigator.clipboard.writeText(referralCode);
      copyMessage = $t('referral.copy_success');
    } catch (error) {
      console.error(error);
      copyMessage = $t('referral.copy_error');
    }
  }

  async function handleShare() {
    copyMessage = '';
    shareMessage = '';

    const text = `${$t('referral.share_text_prefix')} ${referralCode}`;

    if (navigator.share) {
      try {
        await navigator.share({
          title: $t('referral.title'),
          text,
          url: window.location.href,
        });
      } catch (error: any) {
        if (error?.name !== 'AbortError') {
          console.error(error);
          shareMessage = $t('referral.share_error');
        }
      }
    } else {
      try {
        await navigator.clipboard.writeText(`${text}\n${window.location.href}`);
        shareMessage = $t('referral.share_fallback');
      } catch (error) {
        console.error(error);
        shareMessage = $t('referral.share_fallback_error');
      }
    }
  }
</script>

<section class="referral">
  <!-- Header -->
  <header class="referral__header">
    <h1 class="referral__title">{$t('referral.title')}</h1>
    <p class="referral__subtitle">
      {$t('referral.subtitle')}
    </p>
  </header>

  <!-- Referral code card -->
  <section class="referral__code-card">
    <div class="referral__code-header">
      <span class="referral__code-label">{$t('referral.code_label')}</span>
    </div>

    <div class="referral__code-body">
      <div class="referral__code-box" aria-label={$t('referral.code_label')}>
        <span class="referral__code-value">{referralCode}</span>
      </div>

      <div class="referral__code-actions">
        <button type="button" class="referral__btn referral__btn--primary" onclick={handleCopy}>
          {$t('referral.copy_code')}
        </button>
        <button type="button" class="referral__btn referral__btn--outline" onclick={handleShare}>
          {$t('referral.share')}
        </button>
      </div>
    </div>

    {#if copyMessage}
      <p class="referral__message referral__message--success">
        {copyMessage}
      </p>
    {/if}

    {#if shareMessage}
      <p class="referral__message referral__message--info">
        {shareMessage}
      </p>
    {/if}
  </section>

  <!-- Summary stats -->
  <section class="referral__summary">
    <div class="referral__stat-card">
      <span class="referral__stat-label">{$t('referral.total_users')}</span>
      <span class="referral__stat-value">{totalReferredUsers}</span>
    </div>

    <div class="referral__stat-card">
      <span class="referral__stat-label">{$t('referral.total_commission')}</span>
      <span class="referral__stat-value">{formatCurrency(totalCommission)}</span>
    </div>
  </section>

  <!-- Empty state -->
  {#if isEmptyState()}
    <section class="referral__empty">
      <h2 class="referral__empty-title">{$t('referral.empty_title')}</h2>
      <p class="referral__empty-text">
        {$t('referral.empty_text')}
      </p>
      <button type="button" class="referral__btn referral__btn--primary" onclick={handleCopy}>
        {$t('referral.empty_cta')}
      </button>
    </section>
  {/if}

  <!-- Monthly stats table -->
  {#if monthlyStats.length > 0}
    <section class="referral__table-section">
      <h2 class="referral__table-title">{$t('referral.table_title')}</h2>

      <div class="referral__table-wrapper">
        <table class="referral__table">
          <thead>
            <tr>
              <th>{$t('referral.table_month')}</th>
              <th>{$t('referral.table_commission')}</th>
              <th>{$t('referral.table_active_users')}</th>
            </tr>
          </thead>
          <tbody>
            {#each monthlyStats as stat (stat.month)}
              <tr>
                <td>{formatMonth(stat.month)}</td>
                <td>{formatCurrency(stat.commission)}</td>
                <td>{stat.activeUsers}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </section>
  {/if}
</section>

<style>
  .referral {
    display: flex;
    flex-direction: column;
    gap: 2rem;
    padding-block: 1.5rem 3rem;
  }

  .referral__header {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .referral__title {
    margin: 0;
    font-size: 1.75rem;
    font-weight: 600;
  }

  .referral__subtitle {
    margin: 0;
    font-size: 0.95rem;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral__code-card {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    padding: 1.25rem 1.5rem;
    border-radius: 0.75rem;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-elevated, #ffffff);
  }

  .referral__code-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .referral__code-label {
    font-size: 0.9rem;
    font-weight: 500;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral__code-body {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
    align-items: center;
    justify-content: space-between;
  }

  .referral__code-box {
    padding: 0.75rem 1rem;
    border-radius: 0.5rem;
    background: var(--immich-bg-subtle, #f8fafc);
    border: 1px dashed var(--immich-border-subtle, #cbd5f5);
    min-width: 200px;
  }

  .referral__code-value {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
    letter-spacing: 0.08em;
    font-weight: 600;
    font-size: 1rem;
  }

  .referral__code-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
  }

  .referral__btn {
    border-radius: 999px;
    padding: 0.5rem 1.1rem;
    font-size: 0.9rem;
    font-weight: 500;
    border: 1px solid transparent;
    cursor: pointer;
    white-space: nowrap;
    transition:
      transform 0.05s ease-out,
      box-shadow 0.05s ease-out,
      background-color 0.1s ease;
  }

  .referral__btn:active {
    transform: translateY(1px);
    box-shadow: none;
  }

  .referral__btn--primary {
    background: var(--immich-accent, #2563eb);
    color: #ffffff;
    border-color: var(--immich-accent, #2563eb);
  }

  .referral__btn--primary:hover {
    background: var(--immich-accent-strong, #1d4ed8);
  }

  .referral__btn--outline {
    background: transparent;
    color: var(--immich-accent, #2563eb);
    border-color: var(--immich-accent, #2563eb);
  }

  .referral__btn--outline:hover {
    background: rgba(37, 99, 235, 0.06);
  }

  .referral__message {
    margin: 0;
    font-size: 0.8rem;
  }

  .referral__message--success {
    color: #16a34a;
  }

  .referral__message--info {
    color: #2563eb;
  }

  .referral__summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 1rem;
  }

  .referral__stat-card {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 1rem 1.25rem;
    border-radius: 0.75rem;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-elevated, #ffffff);
  }

  .referral__stat-label {
    font-size: 0.85rem;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral__stat-value {
    font-size: 1.25rem;
    font-weight: 600;
  }

  .referral__empty {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 1.5rem 1.75rem;
    border-radius: 0.75rem;
    border: 1px dashed var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-subtle, #f8fafc);
  }

  .referral__empty-title {
    margin: 0;
    font-size: 1.1rem;
    font-weight: 600;
  }

  .referral__empty-text {
    margin: 0 0 0.5rem 0;
    font-size: 0.95rem;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral__table-section {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .referral__table-title {
    margin: 0;
    font-size: 1.1rem;
    font-weight: 600;
  }

  .referral__table-wrapper {
    overflow-x: auto;
    border-radius: 0.75rem;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-elevated, #ffffff);
  }

  .referral__table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.9rem;
  }

  .referral__table thead {
    background: var(--immich-bg-subtle, #f8fafc);
  }

  .referral__table th,
  .referral__table td {
    padding: 0.75rem 1rem;
    text-align: left;
    border-bottom: 1px solid var(--immich-border-subtle, #e2e8f0);
  }

  .referral__table th {
    font-weight: 500;
    color: var(--immich-fg-muted, #64748b);
    white-space: nowrap;
  }

  .referral__table tbody tr:last-child td {
    border-bottom: none;
  }

  @media (max-width: 640px) {
    .referral {
      gap: 1.5rem;
    }

    .referral__code-body {
      flex-direction: column;
      align-items: flex-start;
    }
  }
</style>
