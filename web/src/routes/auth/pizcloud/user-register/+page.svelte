<!-- web/src/routes/auth/pizcloud/user-register/+page.svelte -->
<script lang="ts">
  import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
  import AuthPageLayout from '$lib/components/layouts/AuthPageLayout.svelte';
  import { AppRoute } from '$lib/constants';
  import { getServerErrorMessage, handleError } from '$lib/utils/handle-error';
  import { Alert, Button, Field, Input, PasswordInput, Stack } from '@immich/ui';
  import { locale, t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  // Form fields
  let email = $state('');
  let password = $state('');
  let confirm = $state('');

  // Referral code
  let referralCode = $state('');
  let referralLoading = $state(false);
  let referralError = $state('');
  let referralInfo = $state('');

  // General messages
  let errorMessage = $state('');
  let successMessage = $state('');
  let loading = $state(false);

  interface RegisterPayload {
    email: string;
    password: string;
    name?: string;
    referralCode?: string;
  }

  interface ReferralValidationResponse {
    valid: boolean;
    reason?: 'NOT_FOUND' | 'OWN_CODE' | 'EMPTY_CODE' | string;
    validUntil?: string;
    discountPercent?: number;
  }

  const registerRequest = async (payload: RegisterPayload) => {
    const res = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (res.ok) return;

    let message = '';
    try {
      const json = await res.json();
      message = json?.message ?? '';
    } catch {
      message = await res.text();
    }

    const error = new Error(message || 'Registration failed') as Error & { status?: number };
    error.status = res.status;
    console.log('throwing error', error);
    throw error;
  };

  function formatDisplayDate(date: Date): string {
    const day = String(date.getDate()).padStart(2, '0');
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const year = date.getFullYear();
    return `${day}/${month}/${year}`;
  }

  const validateReferralCode = async (code: string, email?: string): Promise<ReferralValidationResponse> => {
    const trimmed = code.trim();

    const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
    const res = await fetch(`${baseUrl}/api/referral/validate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        code: trimmed,
        email: email?.trim() || undefined,
      }),
    });

    if (!res.ok) {
      let message: string;
      try {
        const json = await res.json();
        message = json?.message ?? '';
      } catch {
        message = await res.text();
      }

      const error = new Error(message || 'Referral validation failed') as Error & {
        status?: number;
      };
      error.status = res.status;
      throw error;
    }

    return (await res.json()) as ReferralValidationResponse;
  };

  const handleValidateReferral = async () => {
    referralError = '';
    referralInfo = '';

    const code = referralCode.trim();
    if (!code) {
      referralError = $t('register_referral.empty_error');
      return;
    }

    referralLoading = true;
    try {
      const result = await validateReferralCode(code, email);

      if (!result.valid) {
        if (result.reason === 'NOT_FOUND') {
          referralError = $t('register_referral.code_not_found');
        } else if (result.reason === 'OWN_CODE') {
          referralError = $t('register_referral.code_own_code');
        } else {
          referralError = $t('register_referral.code_invalid');
        }
        return;
      }

      const discount = result.discountPercent ?? 30;
      let expiry: Date;

      if (result.validUntil) {
        expiry = new Date(result.validUntil);
      } else {
        const now = new Date();
        expiry = new Date(now.getTime());
        expiry.setFullYear(now.getFullYear() + 1);
      }

      const formattedDate = formatDisplayDate(expiry);

      // referralInfo = $t('register_referral.applied_message', {
      //   discount,
      //   date: formattedDate,
      // });
      referralInfo = $t('register_referral.applied_message', { discount, date: formattedDate } as any);
      referralError = '';
    } catch (err) {
      console.error('Error validating referral', err);
      if (!referralError) {
        referralError = $t('register_referral.code_invalid');
      }
    } finally {
      referralLoading = false;
    }
  };

  const handleRegister = async () => {
    try {
      errorMessage = '';
      successMessage = '';

      if (!email) {
        errorMessage = $t('email_required');
        return;
      }
      if (!password) {
        errorMessage = $t('password_required');
        return;
      }
      if (password !== confirm) {
        errorMessage = $t('password_does_not_match');
        return;
      }

      loading = true;

      const payload: RegisterPayload = {
        email,
        password,
      };

      if (referralCode.trim()) {
        payload.referralCode = referralCode.trim();
      }

      await registerRequest(payload);

      try {
        const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
        const currentLocale = $locale || 'en';
        const res = await fetch(`${baseUrl}/auth/verify-email`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ email, lang: currentLocale }),
        });

        if (!res.ok) {
          console.error('Failed to send verification email', await res.text());
          successMessage = $t('registration_success_but_verification_email_failed');
        } else {
          successMessage = $t('verification_email_sent_check_inbox');
        }
      } catch (sendErr) {
        console.error('Error sending verification email', sendErr);
        successMessage = $t('registration_success_but_verification_email_failed');
      }

      password = '';
      confirm = '';
    } catch (err) {
      const status = (err as any)?.status as number | undefined;
      const rawMsg = String((err as any)?.message ?? getServerErrorMessage(err) ?? '').trim();
      const msg = rawMsg.toLowerCase();
      if (
        status === 409 ||
        /user\s+exist/i.test(msg) ||
        /user\s+already\s+exist/i.test(msg) ||
        /already\s+exists/i.test(msg) ||
        /email.*exist/i.test(msg)
      ) {
        errorMessage = $t('email_already_exists');
      } else if (status === 403) {
        errorMessage = $t('server_does_not_allow_self_registration');
      } else if (status === 400) {
        if (/(password|pwd|weak|invalid)/.test(msg)) {
          errorMessage = $t('password_invalid');
        } else {
          errorMessage = rawMsg || $t('registration_failed');
        }
      } else {
        errorMessage = rawMsg || $t('registration_failed');
      }

      handleError(err, $t('registration_failed'));
    } finally {
      loading = false;
    }
  };

  const onsubmit = async (event: Event) => {
    event.preventDefault();
    await handleRegister();
  };
</script>

<AuthPageLayout title={$t(data.meta.title)}>
  <Stack gap={4}>
    <form {onsubmit} class="flex flex-col gap-4">
      {#if errorMessage}
        <Alert color="danger" title={errorMessage} closable />
      {/if}

      {#if successMessage}
        <Alert color="success" title={successMessage} closable />
      {/if}

      <Field label={$t('email')}>
        <Input id="email" name="email" type="email" autocomplete="email" bind:value={email} />
      </Field>

      <Field label={$t('password')}>
        <PasswordInput id="password" bind:value={password} autocomplete="new-password" />
      </Field>

      <Field label={$t('confirm_password')}>
        <PasswordInput id="confirm-password" bind:value={confirm} autocomplete="new-password" />
      </Field>

      <!-- Referral / discount code -->
      <Field label={$t('register_referral.label')}>
        <div class="flex flex-col gap-1">
          <div class="flex gap-2 items-stretch">
            <Input
              id="referral-code"
              name="referral-code"
              autocomplete="off"
              bind:value={referralCode}
              placeholder={$t('register_referral.placeholder')}
            />
            <Button
              type="button"
              size="medium"
              shape="round"
              onclick={handleValidateReferral}
              loading={referralLoading}
              class="mt-8"
            >
              {$t('register_referral.apply')}
            </Button>
          </div>

          <p class="text-xs text-slate-500">
            {$t('register_referral.description')}
          </p>

          {#if referralLoading}
            <p class="text-xs text-slate-500">
              {$t('register_referral.validating')}
            </p>
          {:else if referralError}
            <p class="text-xs text-red-500">
              {referralError}
            </p>
          {:else if referralInfo}
            <p class="text-xs text-emerald-600">
              {referralInfo}
            </p>
          {/if}
        </div>
      </Field>

      <Button type="submit" size="large" shape="round" fullWidth {loading} class="mt-6">
        {$t('sign_up')}
      </Button>
    </form>

    <div class="text-center text-sm mt-2">
      {$t('have_account')}
      <a class="underline" href={AppRoute.AUTH_LOGIN}>{$t('to_login')}</a>
    </div>
  </Stack>
</AuthPageLayout>
