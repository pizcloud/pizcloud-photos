<script lang="ts">
  import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
  import { t } from 'svelte-i18n';

  interface MonthlyStat {
    month: string;
    commission: number;
    activeUsers: number;
  }

  interface ReferrerInfo {
    email: string;
    referralCode?: string | null;
    discountStartAt?: string | null;
    discountEndAt?: string | null;
  }

  interface Props {
    referralCode?: string;
    totalReferredUsers?: number;
    totalCommission?: number;
    monthlyStats?: MonthlyStat[];
    currency?: string;
    referrer?: ReferrerInfo | null;
    userEmail?: string;

    keys?: unknown;
    sessions?: unknown;
  }

  let {
    referralCode = 'ABC123DEF',
    totalReferredUsers = 0,
    totalCommission = 0,
    monthlyStats = [],
    currency = 'VND',
    referrer = null,
    userEmail = '',
    keys,
    sessions,
  }: Props = $props();

  let copyMessage = $state('');
  let shareMessage = $state('');

  let localReferrer = $state<ReferrerInfo | null>(referrer ?? null);
  let applyCode = $state('');
  let applyLoading = $state(false);
  let applyError = $state('');
  let applySuccess = $state('');

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

  function formatDate(dateStr: string | null | undefined): string {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (Number.isNaN(d.getTime())) return dateStr;
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const year = d.getFullYear();
    return `${day}/${month}/${year}`;
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

  async function handleApplyReferrer() {
    applyError = '';
    applySuccess = '';

    const code = applyCode.trim();

    if (!code) {
      applyError = $t('referral.apply_empty_error');
      return;
    }

    if (!userEmail) {
      applyError = $t('referral.apply_missing_email');
      return;
    }

    applyLoading = true;

    try {
      const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
      const res = await fetch(`${baseUrl}/papi/referral/apply-code`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: userEmail, code }),
      });

      if (!res.ok) {
        console.error('Failed to apply referral code', res.status, await res.text());
        applyError = $t('referral.apply_unknown_error');
        return;
      }

      const data = await res.json();

      if (!data?.success) {
        const reason = String(data?.reason || '').toUpperCase();
        if (reason === 'NOT_FOUND') {
          applyError = $t('referral.apply_not_found');
        } else if (reason === 'OWN_CODE') {
          applyError = $t('referral.apply_own_code');
        } else if (reason === 'ALREADY_HAS_REFERRER') {
          applyError = $t('referral.apply_already_has_referrer');
        } else if (reason === 'EMPTY_CODE') {
          applyError = $t('referral.apply_empty_error');
        } else if (reason === 'USER_NOT_FOUND') {
          applyError = $t('referral.apply_missing_email');
        } else {
          applyError = $t('referral.apply_unknown_error');
        }
        return;
      }

      if (data.referrer) {
        localReferrer = {
          email: data.referrer.email,
          referralCode: data.referrer.referralCode ?? null,
          discountStartAt: data.referrer.discountStartAt ?? null,
          discountEndAt: data.referrer.discountEndAt ?? null,
        };
        applyCode = '';
        applySuccess = $t('referral.apply_success', { values: { email: data.referrer.email } });
      } else {
        applyError = $t('referral.apply_unknown_error');
      }
    } catch (err) {
      console.error('Error applying referral code', err);
      applyError = $t('referral.apply_unknown_error');
    } finally {
      applyLoading = false;
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

  <!-- Referrer section -->
  <section class="referral__referrer">
    {#if localReferrer}
      <div class="referral__referrer-card">
        <div class="referral__referrer-header">
          <span class="referral__referrer-label">
            {$t('referral.referrer_applied_title')}
          </span>
        </div>
        <div class="referral__referrer-body">
          <div class="referral__referrer-email">
            {localReferrer.email}
          </div>
          {#if localReferrer.referralCode}
            <div class="referral__referrer-code">
              <span>{$t('referral.referrer_code')}</span>
              <span class="referral__referrer-code-value">
                {localReferrer.referralCode}
              </span>
            </div>
          {/if}
          {#if localReferrer.discountStartAt && localReferrer.discountEndAt}
            <div class="referral__referrer-discount">
              {$t('referral.referrer_discount_range', {
                values: {
                  start: formatDate(localReferrer.discountStartAt),
                  end: formatDate(localReferrer.discountEndAt),
                },
              })}
            </div>
          {/if}
        </div>
      </div>
    {:else}
      <div class="referral__referrer-card referral__referrer-card--empty">
        <div class="referral__referrer-header">
          <span class="referral__referrer-label">
            {$t('referral.referrer_label')}
          </span>
          <span class="referral__referrer-hint">
            {$t('referral.referrer_hint')}
          </span>
        </div>

        <div class="referral__referrer-input-row">
          <input
            class="referral__input"
            type="text"
            placeholder={$t('referral.apply_referrer_placeholder')}
            bind:value={applyCode}
            autocomplete="off"
          />
          <button
            type="button"
            class="referral__btn referral__btn--primary"
            onclick={handleApplyReferrer}
            disabled={applyLoading}
          >
            {#if applyLoading}
              {$t('referral.apply_loading')}
            {:else}
              {$t('referral.apply_referrer_button')}
            {/if}
          </button>
        </div>

        {#if applyError}
          <p class="referral__apply-message referral__apply-message--error">
            {applyError}
          </p>
        {:else if applySuccess}
          <p class="referral__apply-message referral__apply-message--success">
            {applySuccess}
          </p>
        {/if}
      </div>
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

  /* Referrer block */
  .referral__referrer {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .referral__referrer-card {
    padding: 1.1rem 1.25rem;
    border-radius: 0.75rem;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-elevated, #ffffff);
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .referral__referrer-card--empty {
    border-style: dashed;
  }

  .referral__referrer-header {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .referral__referrer-label {
    font-size: 0.9rem;
    font-weight: 500;
  }

  .referral__referrer-hint {
    font-size: 0.8rem;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral__referrer-body {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .referral__referrer-email {
    font-size: 0.95rem;
    font-weight: 500;
  }

  .referral__referrer-code {
    display: flex;
    gap: 0.25rem;
    font-size: 0.85rem;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral__referrer-code-value {
    font-weight: 500;
    color: inherit;
  }

  .referral__referrer-discount {
    font-size: 0.85rem;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral__referrer-input-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: center;
  }

  .referral__input {
    flex: 1 1 180px;
    min-width: 0;
    padding: 0.5rem 0.75rem;
    border-radius: 999px;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-subtle, #f8fafc);
    font-size: 0.9rem;
    outline: none;
  }

  .referral__input:focus {
    border-color: var(--immich-accent, #2563eb);
    box-shadow: 0 0 0 1px rgba(37, 99, 235, 0.15);
  }

  .referral__apply-message {
    margin: 0;
    font-size: 0.8rem;
  }

  .referral__apply-message--error {
    color: #ef4444;
  }

  .referral__apply-message--success {
    color: #16a34a;
  }

  @media (max-width: 640px) {
    .referral {
      gap: 1.5rem;
    }

    .referral__code-body {
      flex-direction: column;
      align-items: flex-start;
    }

    .referral__referrer-input-row {
      flex-direction: column;
      align-items: stretch;
    }

    .referral__btn {
      width: 100%;
      justify-content: center;
      text-align: center;
    }
    .referral__input {
      flex: none;
    }
    .referral__code-box {
      width: 100%;
    }
    .referral__code-actions {
      width: 100%;
      flex-wrap: nowrap;
    }
  }

  /* Dark mode tweaks */
  /* @media (prefers-color-scheme: dark) {
    .referral__code-card,
    .referral__stat-card,
    .referral__empty,
    .referral__table-wrapper,
    .referral__referrer-card {
      background: var(--immich-bg-elevated, #020617);
      border-color: var(--immich-border-subtle, #1e293b);
    }

    .referral__code-box {
      background: var(--immich-bg-subtle, #0b1120);
      border-color: var(--immich-border-subtle, #1f2937);
    }

    .referral__subtitle,
    .referral__stat-label,
    .referral__empty-text,
    .referral__table th,
    .referral__referrer-hint,
    .referral__referrer-discount,
    .referral__referrer-code {
      color: var(--immich-fg-muted, #9ca3af);
    }

    .referral__input {
      background: var(--immich-bg-subtle, #020617);
      border-color: var(--immich-border-subtle, #1f2937);
      color: var(--immich-fg, #e5e7eb);
    }

    .referral__table thead {
      background: var(--immich-bg-subtle, #020617);
    }
  } */
</style>
