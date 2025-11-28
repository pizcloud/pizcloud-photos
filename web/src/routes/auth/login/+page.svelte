<script lang="ts">
  import { goto } from '$app/navigation';
  import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
  import AuthPageLayout from '$lib/components/layouts/AuthPageLayout.svelte';
  import { AppRoute } from '$lib/constants';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
  import { serverConfigManager } from '$lib/managers/server-config-manager.svelte';
  import { oauth } from '$lib/utils';
  import { getServerErrorMessage, handleError } from '$lib/utils/handle-error';
  import { login, type LoginResponseDto } from '@immich/sdk';
  import { Alert, Button, Field, Input, PasswordInput, Stack } from '@immich/ui';
  import { onMount } from 'svelte';
  import { locale, t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let errorMessage: string = $state('');

  let email = $state('');
  let password = $state('');
  let oauthError = $state('');
  let loading = $state(false);
  let oauthLoading = $state(true);

  // pizcloud:
  let successMessage: string = $state('');
  let needsEmailVerification = $state(false);
  let resendLoading = $state(false);
  // #pizcloud

  const serverConfig = $derived(serverConfigManager.value);

  const onSuccess = async (user: LoginResponseDto) => {
    await goto(data.continueUrl, { invalidateAll: true });
    eventManager.emit('AuthLogin', user);
  };

  const onFirstLogin = () => goto(AppRoute.AUTH_CHANGE_PASSWORD);
  const onOnboarding = () => goto(AppRoute.AUTH_ONBOARDING);

  onMount(async () => {
    if (!featureFlagsManager.value.oauth) {
      oauthLoading = false;
      return;
    }

    if (oauth.isCallback(globalThis.location)) {
      try {
        const user = await oauth.login(globalThis.location);

        if (!user.isOnboarded) {
          await onOnboarding();
          return;
        }

        await onSuccess(user);
        return;
      } catch (error) {
        console.error('Error [login-form] [oauth.callback]', error);
        oauthError = getServerErrorMessage(error) || $t('errors.unable_to_complete_oauth_login');
        oauthLoading = false;
        return;
      }
    }

    try {
      if (
        (featureFlagsManager.value.oauthAutoLaunch && !oauth.isAutoLaunchDisabled(globalThis.location)) ||
        oauth.isAutoLaunchEnabled(globalThis.location)
      ) {
        await goto(`${AppRoute.AUTH_LOGIN}?autoLaunch=0`, { replaceState: true });
        await oauth.authorize(globalThis.location);
        return;
      }
    } catch (error) {
      handleError(error, $t('errors.unable_to_connect'));
    }

    oauthLoading = false;
  });

  // pizcloud
  const checkEmailVerification = async (): Promise<boolean> => {
    const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
    if (!baseUrl || !email) {
      return true;
    }

    try {
      const res = await fetch(`${baseUrl}/auth/email-verification-status?email=${encodeURIComponent(email)}`, {
        method: 'GET',
        headers: { accept: 'application/json' },
      });

      if (res.ok) {
        const json = await res.json();
        if (json && json.verified === false) {
          needsEmailVerification = true;
          errorMessage = $t('errors.email_not_verified');
          return false;
        }
        needsEmailVerification = false;
        return true;
      } else {
        console.error('Failed to check email verification status', await res.text());
        return true;
      }
    } catch (err) {
      console.error('Error calling att-server for email verification status', err);
      return true;
    }
  };

  const handleResendVerification = async () => {
    try {
      successMessage = '';
      if (!email) {
        errorMessage = $t('errors.email_required_for_resend');
        return;
      }

      const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');
      if (!baseUrl) {
        errorMessage = $t('errors.resend_verification_email_failed');
        return;
      }

      resendLoading = true;

      const currentLocale = $locale || 'en';

      const res = await fetch(`${baseUrl}/auth/verify-email`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email, lang: currentLocale }),
      });

      if (res.ok) {
        successMessage = $t('verification_email_resent');
        errorMessage = '';
        needsEmailVerification = false;
      } else {
        console.error('Failed to resend verification email', await res.text());
        errorMessage = $t('errors.resend_verification_email_failed');
      }
    } catch (error) {
      console.error('Error resending verification email', error);
      errorMessage = $t('errors.resend_verification_email_failed');
    } finally {
      resendLoading = false;
    }
  };
  // #pizcloud

  const handleLogin = async () => {
    try {
      errorMessage = '';
      successMessage = '';
      needsEmailVerification = false;
      loading = true;
      const user = await login({ loginCredentialDto: { email, password } });

      // pizcloud: call to check if the email has been verified
      const ok = await checkEmailVerification();
      if (!ok) {
        loading = false;
        return;
      }
      // #pizcloud

      if (user.isAdmin && !serverConfig.isOnboarded) {
        await onOnboarding();
        return;
      }

      // change the user password before we onboard them
      if (!user.isAdmin && user.shouldChangePassword) {
        await onFirstLogin();
        return;
      }

      // We want to onboard after the first login since their password will change
      // and handleLogin will be called again (relogin). We then do onboarding on that next call.
      if (!user.isOnboarded) {
        await onOnboarding();
        return;
      }

      await onSuccess(user);
      return;
    } catch (error) {
      errorMessage = getServerErrorMessage(error) || $t('errors.incorrect_email_or_password');
      loading = false;
      return;
    }
  };

  const handleOAuthLogin = async () => {
    oauthLoading = true;
    oauthError = '';
    const success = await oauth.authorize(globalThis.location);
    if (!success) {
      oauthLoading = false;
      oauthError = $t('errors.unable_to_login_with_oauth');
    }
  };

  const onsubmit = async (event: Event) => {
    event.preventDefault();
    await handleLogin();
  };
</script>

<AuthPageLayout title={data.meta.title}>
  <Stack gap={4}>
    {#if serverConfig.loginPageMessage}
      <Alert color="primary" class="mb-6">
        <!-- eslint-disable-next-line svelte/no-at-html-tags -->
        {@html serverConfig.loginPageMessage}
      </Alert>
    {/if}

    {#if !oauthLoading && featureFlagsManager.value.passwordLogin}
      <form {onsubmit} class="flex flex-col gap-4">
        {#if errorMessage}
          <Alert color="danger" title={errorMessage} closable />
        {/if}

        <!-- pizcloud -->
        {#if successMessage}
          <Alert color="primary" title={successMessage} closable />
        {/if}
        <!-- #pizcloud -->

        <Field label={$t('email')}>
          <Input id="email" name="email" type="email" autocomplete="email" bind:value={email} />
        </Field>

        <Field label={$t('password')}>
          <PasswordInput id="password" bind:value={password} autocomplete="current-password" />
        </Field>

        <Button type="submit" size="large" shape="round" fullWidth {loading} class="mt-6">{$t('to_login')}</Button>

        <!-- pizcloud -->
        {#if needsEmailVerification}
          <Button
            type="button"
            size="medium"
            shape="round"
            fullWidth
            class="mt-2"
            loading={resendLoading}
            onclick={handleResendVerification}
          >
            {$t('resend_verification_email')}
          </Button>
        {/if}
        <!-- #pizcloud -->
      </form>
    {/if}

    {#if featureFlagsManager.value.oauth}
      {#if featureFlagsManager.value.passwordLogin}
        <div class="inline-flex w-full items-center justify-center my-4">
          <hr class="my-4 h-px w-3/4 border-0 bg-gray-200 dark:bg-gray-600" />
          <span
            class="absolute start-1/2 -translate-x-1/2 bg-gray-50 px-3 font-medium text-gray-900 dark:bg-neutral-900 dark:text-white uppercase"
          >
            {$t('or')}
          </span>
        </div>
      {/if}
      {#if oauthError}
        <Alert color="danger" title={oauthError} closable />
      {/if}
      <Button
        shape="round"
        loading={loading || oauthLoading}
        disabled={loading || oauthLoading}
        size="large"
        fullWidth
        color={featureFlagsManager.value.passwordLogin ? 'secondary' : 'primary'}
        onclick={handleOAuthLogin}
      >
        {serverConfig.oauthButtonText}
      </Button>
    {/if}

    {#if featureFlagsManager.value.passwordLogin}
      <div class="text-center text-sm mt-2">
        {$t('no_account_yet')}
        <a class="underline" href={AppRoute.AUTH_USER_REGISTER}>{$t('sign_up')}</a>
      </div>
    {/if}

    {#if !featureFlagsManager.value.passwordLogin && !featureFlagsManager.value.oauth}
      <Alert color="warning" title={$t('login_has_been_disabled')} />
    {/if}
  </Stack>
</AuthPageLayout>
