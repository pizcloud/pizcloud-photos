<script lang="ts">
  import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
  import { onMount } from 'svelte';
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

  type ReferralWithdrawStatus = 'pending' | 'approved' | 'rejected' | 'paid';

  interface ReferralPayoutMethod {
    method?: 'bank' | 'paypal' | null;
    bankName?: string | null;
    bankAccountNumber?: string | null;
    bankAccountHolderName?: string | null;
    paypalEmail?: string | null;
    paypalFullName?: string | null;
  }

  interface Props {
    referralCode?: string;
    totalReferredUsers?: number;
    totalCommission?: number;
    monthlyStats?: MonthlyStat[];
    currency?: string;
    referrer?: ReferrerInfo | null;
    userEmail?: string;

    //extra summary fields
    availableBalance?: number;
    pendingWithdrawalAmount?: number;
    totalRequestedWithdrawal?: number;
    totalPaidWithdrawal?: number;
    totalRejectedWithdrawal?: number;

    //config
    minWithdrawAmount?: number;
    payoutMethodUrl?: string;
    withdrawalHistoryUrl?: string;

    keys?: unknown;
    sessions?: unknown;
  }

  let {
    referralCode = 'ABC123DEF',
    totalReferredUsers = 0,
    totalCommission = 0,
    monthlyStats = [],
    currency = 'USD',
    referrer = null,
    userEmail = '',

    availableBalance = 0,
    pendingWithdrawalAmount = 0,
    totalRequestedWithdrawal = 0,
    totalPaidWithdrawal = 0,
    totalRejectedWithdrawal = 0,
    minWithdrawAmount = 5,
    payoutMethodUrl = '/pizcloud/payout-method',
    withdrawalHistoryUrl = '/pizcloud/withdrawals',

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

  // withdraw + payout state
  let payoutMethod = $state<ReferralPayoutMethod | null>(null);
  let withdrawModalOpen = $state(false);
  let withdrawAmount = $state<string>('');
  let withdrawError = $state('');
  let withdrawSuccess = $state('');
  let withdrawSubmitting = $state(false);

  const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');

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
      const res = await fetch(`${baseUrl}/referral/apply-code`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        credentials: 'include',
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

  // ========== payout method & withdraw logic ==========

  async function loadPayoutMethod() {
    if (!userEmail) {
      payoutMethod = null;
      return;
    }

    try {
      const res = await fetch(`${baseUrl}/referral/payout-method`, {
        credentials: 'include',
      });

      if (!res.ok) {
        payoutMethod = null;
        return;
      }

      const data = await res.json();
      payoutMethod = {
        method: data.method ?? null,
        bankName: data.bankName ?? null,
        bankAccountNumber: data.bankAccountNumber ?? null,
        bankAccountHolderName: data.bankAccountHolderName ?? null,
        paypalEmail: data.paypalEmail ?? null,
        paypalFullName: data.paypalFullName ?? null,
      };
    } catch (e) {
      console.error('Error loading payout method', e);
      payoutMethod = null;
    }
  }

  function hasInfoFor(method: 'bank' | 'paypal'): boolean {
    if (!payoutMethod) return false;
    if (method === 'bank') {
      return !!payoutMethod.bankName && !!payoutMethod.bankAccountNumber && !!payoutMethod.bankAccountHolderName;
    }
    return !!payoutMethod.paypalEmail;
  }

  const currentBalance = () => {
    if (typeof availableBalance === 'number' && Number.isFinite(availableBalance)) {
      return availableBalance;
    }

    if (typeof totalCommission === 'number' && Number.isFinite(totalCommission)) {
      return totalCommission;
    }

    return 0;
  };

  function normalizeToTwoDecimals(value: number): number {
    if (!Number.isFinite(value)) return 0;
    const cents = Math.round((value + Number.EPSILON) * 100);
    return cents / 100;
  }

  function applyWithdrawLocally(amount: number) {
    const normalized = normalizeToTwoDecimals(amount);

    const prevBalance = normalizeToTwoDecimals(currentBalance());
    const newBalanceRaw = prevBalance - normalized;
    const newBalance = newBalanceRaw <= 0 ? 0 : normalizeToTwoDecimals(newBalanceRaw);

    availableBalance = newBalance;

    const prevPending =
      typeof pendingWithdrawalAmount === 'number' && Number.isFinite(pendingWithdrawalAmount)
        ? pendingWithdrawalAmount
        : 0;
    pendingWithdrawalAmount = normalizeToTwoDecimals(prevPending + normalized);

    const prevTotalRequested =
      typeof totalRequestedWithdrawal === 'number' && Number.isFinite(totalRequestedWithdrawal)
        ? totalRequestedWithdrawal
        : 0;
    totalRequestedWithdrawal = normalizeToTwoDecimals(prevTotalRequested + normalized);
  }

  function canWithdraw() {
    return currentBalance() >= minWithdrawAmount;
  }

  function openWithdrawModal() {
    withdrawError = '';
    withdrawSuccess = '';
    withdrawSubmitting = false;

    if (!userEmail) {
      withdrawError = $t('referral.withdraw_missing_email');
      return;
    }

    const bal = currentBalance();
    withdrawAmount = bal > 0 ? bal.toFixed(2) : '';
    withdrawModalOpen = true;
  }

  function closeWithdrawModal() {
    withdrawModalOpen = false;
    withdrawSubmitting = false;
  }

  function stopModalClick(event: MouseEvent) {
    event.stopPropagation();
  }

  async function submitWithdraw() {
    if (withdrawSubmitting) {
      return;
    }

    if (!userEmail) {
      withdrawError = $t('referral.withdraw_missing_email');
      return;
    }

    withdrawError = '';
    withdrawSuccess = '';
    withdrawSubmitting = true;

    try {
      const rawValue = (withdrawAmount ?? '').toString();
      const raw = rawValue.trim().replace(/,/g, '');
      const parsed = Number(raw);

      if (!Number.isFinite(parsed) || parsed <= 0) {
        withdrawError = $t('referral.withdraw_amount_invalid');
        return;
      }

      const amount = normalizeToTwoDecimals(parsed);
      const balance = normalizeToTwoDecimals(currentBalance());

      if (amount < minWithdrawAmount) {
        withdrawError = $t('referral.withdraw_min_error', {
          values: { min: minWithdrawAmount.toFixed(2) },
        });
        return;
      }

      if (amount - balance > 1e-6) {
        withdrawError = $t('referral.withdraw_balance_insufficient');
        return;
      }

      const method: 'bank' | 'paypal' = payoutMethod?.method === 'paypal' ? 'paypal' : 'bank';

      if (!hasInfoFor(method)) {
        withdrawError =
          method === 'bank' ? $t('referral.withdraw_bank_info_required') : $t('referral.withdraw_paypal_info_required');
        return;
      }

      const res = await fetch(`${baseUrl}/referral/withdrawals`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          email: userEmail,
          amount,
          currency,
          method,
        }),
      });

      if (!res.ok) {
        let code: string | undefined;
        try {
          const body = await res.json();
          const msg = body?.message;
          if (typeof msg === 'string') code = msg;
        } catch {
          // ignore
        }

        switch (code) {
          case 'MIN_TOTAL_COMMISSION_NOT_REACHED':
            withdrawError = $t('referral.withdraw_min_total_not_reached', {
              values: { min: minWithdrawAmount.toFixed(2) },
            });
            break;
          case 'AMOUNT_EXCEEDS_BALANCE':
          case 'AMOUNT_EXCEEDS_AVAILABLE_AFTER_PENDING':
            withdrawError = $t('referral.withdraw_balance_insufficient');
            break;
          case 'INVALID_AMOUNT':
            withdrawError = $t('referral.withdraw_amount_invalid');
            break;
          case 'INVALID_WITHDRAW_METHOD':
            withdrawError = $t('referral.withdraw_method_invalid');
            break;
          case 'BANK_INFO_REQUIRED':
            withdrawError = $t('referral.withdraw_bank_info_required');
            break;
          case 'PAYPAL_INFO_REQUIRED':
            withdrawError = $t('referral.withdraw_paypal_info_required');
            break;
          case 'USER_NOT_FOUND':
          case 'EMAIL_REQUIRED':
            withdrawError = $t('referral.apply_missing_email');
            break;
          default:
            withdrawError = $t('referral.withdraw_request_error');
        }

        return;
      }

      applyWithdrawLocally(amount);
      withdrawSuccess = $t('referral.withdraw_request_success');
      closeWithdrawModal();
    } catch (e) {
      console.error('Error requesting withdrawal', e);
      withdrawError = $t('referral.withdraw_request_error');
    } finally {
      withdrawSubmitting = false;
    }
  }

  onMount(() => {
    loadPayoutMethod();
  });
</script>

<section class="referral">
  <!-- Header -->
  <header class="referral__header">
    <h1 class="referral__title">{$t('referral.discount_code')}</h1>
  </header>

  <!-- Referrer section -->
  <section class="referral__referrer">
    {#if localReferrer}
      <div class="referral__referrer-card">
        <div class="referral__referrer-header">
          <span class="referral__referrer-label">
            {$t('referral.your_discount_code')}
          </span>
        </div>
        <div class="referral__referrer-body">
          <div class="referral__referrer-email">
            <span>{$t('referral.referrer_label')}:</span>
            <span class="referral__referrer-code-value code-bold-value">
              {localReferrer.email}
            </span>
          </div>
          {#if localReferrer.referralCode}
            <div class="referral__referrer-code">
              <span>{$t('referral.referrer_code')}</span>
              <span class="referral__referrer-code-value code-bold-value">
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
    color: var(--immich-fg-muted, #64748b);
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

  .code-bold-value {
    color: #000000;
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
  }

  /* dark mode styles */
  :global(.dark) .referral {
    color: rgb(var(--immich-dark-fg, 229 231 235));
  }

  :global(.dark) .referral__referrer-card {
    background: rgb(var(--immich-dark-gray, 33 33 33));
    border-color: rgba(148, 163, 184, 0.2);
  }

  :global(.dark) .referral__input {
    background: rgb(var(--immich-dark-bg, 10 10 10));
    border-color: rgba(148, 163, 184, 0.25);
    color: rgb(var(--immich-dark-fg, 229 231 235));
  }

  :global(.dark) .referral__referrer-hint,
  :global(.dark) .referral__referrer-discount,
  :global(.dark) .referral__referrer-code,
  :global(.dark) .referral__referrer-email {
    color: rgba(229, 231, 235, 0.7);
  }

  :global(.dark) .referral__btn--primary {
    background: rgb(var(--immich-dark-primary, 172 203 250));
    color: rgb(var(--immich-dark-bg, 10 10 10));
    border-color: rgb(var(--immich-dark-primary, 172 203 250));
  }

  :global(.dark) .referral__btn--primary:hover {
    background: rgba(172, 203, 250, 0.9);
  }

  :global(.dark) .code-bold-value {
    color: rgb(var(--immich-dark-fg, 229 231 235));
  }

  @media (max-width: 640px) {
  }
</style>
