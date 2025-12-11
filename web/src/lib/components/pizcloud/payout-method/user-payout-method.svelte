<script lang="ts">
  import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  interface ReferralPayoutMethod {
    method?: 'bank' | 'paypal' | null;
    bankName?: string | null;
    bankAccountNumber?: string | null;
    bankAccountHolderName?: string | null;
    paypalEmail?: string | null;
    paypalFullName?: string | null;
  }

  interface Props {
    userEmail: string;
  }

  let { userEmail }: Props = $props();

  let loading = $state(true);
  let saving = $state(false);
  let error = $state('');
  let success = $state('');

  let method = $state<'bank' | 'paypal'>('bank');

  let bankName = $state('');
  let bankAccountNumber = $state('');
  let bankAccountHolderName = $state('');

  let paypalEmail = $state('');
  let paypalFullName = $state('');

  function getBaseUrl() {
    return (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
  }

  async function load() {
    if (!userEmail) {
      error = $t('referral.apply_missing_email');
      loading = false;
      return;
    }

    loading = true;
    error = '';

    try {
      const base = getBaseUrl();
      const url = new URL('/papi/referral/payout-method', base);
      url.searchParams.set('email', userEmail);

      const res = await fetch(url.toString(), {
        credentials: 'include',
      });

      if (!res.ok) {
        loading = false;
        return;
      }

      const data: ReferralPayoutMethod = await res.json();

      method = data.method === 'paypal' ? 'paypal' : 'bank';
      bankName = data.bankName ?? '';
      bankAccountNumber = data.bankAccountNumber ?? '';
      bankAccountHolderName = data.bankAccountHolderName ?? '';
      paypalEmail = data.paypalEmail ?? '';
      paypalFullName = data.paypalFullName ?? '';
    } catch (e) {
      console.error('Error loading payout method', e);
      error = $t('referral.payout_method_load_error');
    } finally {
      loading = false;
    }
  }

  function validate(): boolean {
    error = '';
    if (method === 'bank') {
      if (!bankName.trim() || !bankAccountNumber.trim() || !bankAccountHolderName.trim()) {
        error = $t('referral.withdraw_bank_info_required');
        return false;
      }
    } else {
      if (!paypalEmail.trim()) {
        error = $t('referral.withdraw_paypal_info_required');
        return false;
      }
    }
    return true;
  }

  async function save() {
    if (!userEmail) {
      error = $t('referral.apply_missing_email');
      return;
    }

    if (!validate()) return;

    saving = true;
    error = '';
    success = '';

    try {
      const base = getBaseUrl();
      const res = await fetch(`${base}/papi/referral/payout-method`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email: userEmail,
          method,
          bankName,
          bankAccountNumber,
          bankAccountHolderName,
          paypalEmail,
          paypalFullName,
        }),
      });

      if (!res.ok) {
        let code: string | undefined;
        try {
          const body = await res.json();
          if (typeof body?.message === 'string') {
            code = body.message;
          }
        } catch {
          // ignore
        }

        switch (code) {
          case 'BANK_INFO_REQUIRED':
            error = $t('referral.withdraw_bank_info_required');
            break;
          case 'PAYPAL_INFO_REQUIRED':
            error = $t('referral.withdraw_paypal_info_required');
            break;
          case 'INVALID_WITHDRAW_METHOD':
            error = $t('referral.withdraw_method_invalid');
            break;
          case 'EMAIL_REQUIRED':
          case 'USER_NOT_FOUND':
            error = $t('referral.apply_missing_email');
            break;
          default:
            error = $t('referral.payout_method_save_error');
        }
        return;
      }

      // success
      success = $t('referral.payout_method_save_success');
    } catch (e) {
      console.error('Error saving payout method', e);
      error = $t('referral.payout_method_save_error');
    } finally {
      saving = false;
    }
  }

  onMount(load);
</script>

<section class="referral-payout">
  <div class="referral-payout__back">
    <a href="/pizcloud/referral" class="referral-payout__back-link">
      <span class="referral-payout__back-icon">←</span>
      <span>{$t('back')}</span>
    </a>
  </div>
  <header class="referral-payout__header">
    <h1 class="referral-payout__title">
      {$t('referral.payout_method_title')}
    </h1>
    <p class="referral-payout__subtitle">
      {$t('referral.payout_method_description')}
    </p>
  </header>

  {#if loading}
    <div class="referral-payout__loading">
      <div class="spinner"></div>
    </div>
  {:else}
    <div class="referral-payout__content">
      <div class="referral-payout__method-row">
        <span class="referral-payout__label">
          {$t('referral.withdraw_method_label')}
        </span>
        <div class="referral-payout__chips">
          <button
            type="button"
            class:referral-payout__chip--active={method === 'bank'}
            class="referral-payout__chip"
            onclick={() => {
              method = 'bank';
              error = '';
              success = '';
            }}
          >
            {$t('referral.withdraw_method_bank')}
          </button>
          <button
            type="button"
            class:referral-payout__chip--active={method === 'paypal'}
            class="referral-payout__chip"
            onclick={() => {
              method = 'paypal';
              error = '';
              success = '';
            }}
          >
            {$t('referral.withdraw_method_paypal')}
          </button>
        </div>
      </div>

      {#if method === 'bank'}
        <div class="referral-payout__fields">
          <label class="referral-payout__field">
            <span>{$t('referral.withdraw_bank_name_label')}</span>
            <input type="text" bind:value={bankName} placeholder={$t('referral.withdraw_bank_name_hint')} />
          </label>
          <label class="referral-payout__field">
            <span>{$t('referral.withdraw_bank_account_label')}</span>
            <input type="text" bind:value={bankAccountNumber} placeholder={$t('referral.withdraw_bank_account_hint')} />
          </label>
          <label class="referral-payout__field">
            <span>{$t('referral.withdraw_bank_account_holder_label')}</span>
            <input
              type="text"
              bind:value={bankAccountHolderName}
              placeholder={$t('referral.withdraw_bank_account_holder_hint')}
            />
          </label>
        </div>
      {:else}
        <div class="referral-payout__fields">
          <label class="referral-payout__field">
            <span>{$t('referral.withdraw_paypal_email_label')}</span>
            <input type="email" bind:value={paypalEmail} placeholder={$t('referral.withdraw_paypal_email_hint')} />
          </label>
          <label class="referral-payout__field">
            <span>{$t('referral.withdraw_paypal_fullname_label')}</span>
            <input type="text" bind:value={paypalFullName} placeholder={$t('referral.withdraw_paypal_fullname_hint')} />
          </label>
        </div>
      {/if}

      {#if error}
        <p class="referral-payout__error">
          {error}
        </p>
      {/if}

      {#if success}
        <p class="referral-payout__success">
          {success}
        </p>
      {/if}

      <div class="referral-payout__actions">
        <button
          type="button"
          class="referral-payout__btn referral-payout__btn--primary"
          onclick={save}
          disabled={saving}
        >
          {#if saving}
            {$t('referral.payout_method_saving')}
          {:else}
            {$t('referral.payout_method_save_button')}
          {/if}
        </button>
      </div>
    </div>
  {/if}
</section>

<style>
  .referral-payout {
    padding-block: 1.5rem 3rem;
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }

  .referral-payout__back {
    margin-bottom: 0.25rem;
  }

  .referral-payout__back-link {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.85rem;
    text-decoration: none;
    color: var(--immich-accent, #2563eb);
  }

  .referral-payout__back-link:hover {
    text-decoration: underline;
  }

  .referral-payout__back-icon {
    font-size: 1rem;
    line-height: 1;
  }

  .referral-payout__header {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .referral-payout__title {
    margin: 0;
    font-size: 1.5rem;
    font-weight: 600;
  }

  .referral-payout__subtitle {
    margin: 0;
    font-size: 0.95rem;
    color: var(--immich-fg-muted, #64748b);
  }

  .referral-payout__content {
    padding: 1.25rem 1.5rem;
    border-radius: 0.75rem;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-elevated, #ffffff);
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .referral-payout__method-row {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .referral-payout__label {
    font-size: 0.9rem;
    font-weight: 500;
  }

  .referral-payout__chips {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .referral-payout__chip {
    border-radius: 999px;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-subtle, #f8fafc);
    padding: 0.35rem 0.9rem;
    font-size: 0.85rem;
    cursor: pointer;
  }

  .referral-payout__chip--active {
    border-color: var(--immich-accent, #2563eb);
    background: rgba(37, 99, 235, 0.08);
    color: var(--immich-accent, #2563eb);
  }

  .referral-payout__fields {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .referral-payout__field {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    font-size: 0.85rem;
  }

  .referral-payout__field input {
    padding: 0.5rem 0.75rem;
    border-radius: 0.5rem;
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    background: var(--immich-bg-subtle, #f8fafc);
    font-size: 0.9rem;
    outline: none;
  }

  .referral-payout__field input:focus {
    border-color: var(--immich-accent, #2563eb);
    box-shadow: 0 0 0 1px rgba(37, 99, 235, 0.15);
  }

  .referral-payout__error {
    font-size: 0.85rem;
    color: #ef4444;
  }

  .referral-payout__actions {
    display: flex;
    justify-content: flex-end;
  }

  .referral-payout__btn {
    border-radius: 999px;
    padding: 0.5rem 1.4rem;
    border: 1px solid transparent;
    font-size: 0.9rem;
    font-weight: 500;
    cursor: pointer;
  }

  .referral-payout__btn--primary {
    background: var(--immich-accent, #2563eb);
    color: #fff;
    border-color: var(--immich-accent, #2563eb);
  }

  .referral-payout__loading {
    display: flex;
    justify-content: center;
    padding: 2rem 0;
  }

  .spinner {
    width: 24px;
    height: 24px;
    border-radius: 999px;
    border: 3px solid #e2e8f0;
    border-top-color: var(--immich-accent, #2563eb);
    animation: spin 0.75s linear infinite;
  }

  .referral-payout__success {
    font-size: 0.85rem;
    color: #16a34a;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
