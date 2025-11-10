<!-- web/src/routes/auth/user-register/+page.svelte -->
<script lang="ts">
  import { goto } from '$app/navigation';
  import AuthPageLayout from '$lib/components/layouts/AuthPageLayout.svelte';
  import { AppRoute } from '$lib/constants';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { getServerErrorMessage, handleError } from '$lib/utils/handle-error';
  import { login, type LoginResponseDto } from '@immich/sdk';
  import { Alert, Button, Field, Input, PasswordInput, Stack } from '@immich/ui';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }
  let { data }: Props = $props();

  let email = $state('');
  let password = $state('');
  let confirm = $state('');
  let errorMessage = $state('');
  let loading = $state(false);

  const onSuccess = async (user: LoginResponseDto) => {
    await goto(data.continueUrl, { invalidateAll: true });
    eventManager.emit('auth.login', user);
  };

  const onFirstLogin = () => goto(AppRoute.AUTH_CHANGE_PASSWORD);
  const onOnboarding = () => goto(AppRoute.AUTH_ONBOARDING);

  const registerRequest = async (payload: { email: string; password: string; name?: string }) => {
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

  const handleRegister = async () => {
    try {
      errorMessage = '';

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

      await registerRequest({ email, password });

      const user = await login({ loginCredentialDto: { email, password } });

      if (user.isAdmin && user.isOnboarded === false) {
        await onOnboarding();
        return;
      }

      if (!user.isAdmin && user.shouldChangePassword) {
        await onFirstLogin();
        return;
      }

      if (!user.isOnboarded) {
        await onOnboarding();
        return;
      }

      await onSuccess(user);
    } catch (err) {
      const status = (err as any)?.status as number | undefined;
      const rawMsg = String((err as any)?.message ?? getServerErrorMessage(err) ?? '').trim();
      const msg = rawMsg.toLowerCase();
      console.log('msg', msg);
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

      <Field label={$t('email')}>
        <Input id="email" name="email" type="email" autocomplete="email" bind:value={email} />
      </Field>

      <Field label={$t('password')}>
        <PasswordInput id="password" bind:value={password} autocomplete="new-password" />
      </Field>

      <Field label={$t('confirm_password')}>
        <PasswordInput id="confirm-password" bind:value={confirm} autocomplete="new-password" />
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
