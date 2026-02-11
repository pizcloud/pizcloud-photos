<script lang="ts">
  import { invalidate } from '$app/navigation';
  import { t } from 'svelte-i18n';
  import {
    Button,
    Icon,
    IconButton,
    Input,
    Modal,
    ModalBody,
    Stack,
    Text,
    modalManager,
    toastManager,
  } from '@immich/ui';
  import { mdiCheck, mdiClose, mdiDeleteOutline, mdiSwapHorizontal } from '@mdi/js';
  import type { AlbumResponseDto } from '@immich/sdk';
  import { handleError } from '$lib/utils/handle-error';
  import { addSharedEmail, getSharedEmails, removeSharedEmail } from '$lib/services/pizcloud/album-share-email.service';
  import { resolveAlbumShareEmails } from '$lib/services/pizcloud/album-share-resolve.service';
  import {
    cancelAlbumTransfer,
    getAlbumTransfer,
    isPendingTransfer,
    requestAlbumTransfer,
    type AlbumTransferDto,
  } from '$lib/services/pizcloud/album-transfer.service';
  import { albumTransferManager, TransferRefreshReason } from '$lib/stores/album-transfer-manager.svelte';

  interface Props {
    album: AlbumResponseDto;
    onClose: (result?: { action: 'refreshAlbum' }) => void;
  }

  let { album, onClose }: Props = $props();

  type SharedEmailDto = { email: string; createdAt: string };

  let sharedEmails: SharedEmailDto[] = $state([]);
  let pendingTransfer: AlbumTransferDto | null = $state(null);
  let selectedEmail = $state<string>('');
  let emailInput = $state('');
  let loading = $state(true);
  let isSubmitting = $state(false);
  let didChange = $state(false);

  const normalizeEmail = (value: string) => value.trim().toLowerCase();
  const hasPendingTransfer = $derived(isPendingTransfer(pendingTransfer));

  const loadData = async () => {
    loading = true;

    try {
      const [emails, transfer] = await Promise.all([getSharedEmails(album.id), getAlbumTransfer(album.id)]);
      sharedEmails = emails;
      pendingTransfer = transfer;

      if (selectedEmail) {
        const exists = emails.some((item) => normalizeEmail(item.email) === selectedEmail);
        if (!exists) {
          selectedEmail = '';
        }
      }
    } catch (error) {
      handleError(error, $t('transfer_request_failed'));
    } finally {
      loading = false;
    }
  };

  const refreshAfterMutation = async ({ includeIncoming }: { includeIncoming: boolean }) => {
    await albumTransferManager.refresh({
      ownedAlbumIds: [album.id],
      reason: TransferRefreshReason.LocalMutation,
      force: true,
      includeIncoming,
    });

    await invalidate('app:albums');
  };

  const onSaveEmail = async () => {
    const email = normalizeEmail(emailInput);
    if (!email) {
      toastManager.info($t('email_required'));
      return;
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      toastManager.info($t('invalid_email'));
      return;
    }

    try {
      isSubmitting = true;
      await addSharedEmail(album.id, email);
      selectedEmail = email;
      emailInput = '';
      didChange = true;
      await loadData();
      toastManager.success($t('add_successfully'));
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      isSubmitting = false;
    }
  };

  const onRemoveEmail = async (email: string) => {
    try {
      isSubmitting = true;
      await removeSharedEmail(album.id, email);
      if (selectedEmail === normalizeEmail(email)) {
        selectedEmail = '';
      }
      didChange = true;
      await loadData();
      toastManager.success($t('removed'));
    } catch (error) {
      handleError(error, $t('remove_failed'));
    } finally {
      isSubmitting = false;
    }
  };

  const onRequestTransfer = async () => {
    if (!selectedEmail) {
      toastManager.info($t('transfer_select_email'));
      return;
    }

    try {
      isSubmitting = true;
      const resolution = await resolveAlbumShareEmails(album.id, [selectedEmail]);

      if (resolution.missingEmails.length > 0) {
        const preview = resolution.missingEmails.slice(0, 3).join(', ');
        const suffix = resolution.missingEmails.length > 3 ? '...' : '';
        toastManager.info(`Not found in Pizcloud: ${preview}${suffix}`);
        return;
      }

      if (resolution.userIds.length === 0) {
        toastManager.info($t('transfer_user_not_found'));
        return;
      }

      pendingTransfer = await requestAlbumTransfer(album.id, resolution.userIds[0]);
      albumTransferManager.setTransfer(album.id, pendingTransfer);
      didChange = true;
      await refreshAfterMutation({ includeIncoming: false });
      toastManager.success($t('transfer_request_sent'));
    } catch (error) {
      handleError(error, $t('transfer_request_failed'));
    } finally {
      isSubmitting = false;
    }
  };

  const onCancelTransfer = async () => {
    const confirmed = await modalManager.showDialog({
      icon: false,
      title: $t('transfer_cancel_title'),
      prompt: $t('transfer_cancel_confirm'),
      confirmText: $t('confirm'),
    });

    if (!confirmed) {
      return;
    }

    try {
      isSubmitting = true;
      pendingTransfer = await cancelAlbumTransfer(album.id);
      albumTransferManager.setTransfer(album.id, null);
      didChange = true;
      await refreshAfterMutation({ includeIncoming: false });
      await loadData();
      toastManager.success($t('transfer_request_canceled'));
    } catch (error) {
      handleError(error, $t('transfer_request_failed'));
    } finally {
      isSubmitting = false;
    }
  };

  const toggleSelectedEmail = (email: string) => {
    const normalized = normalizeEmail(email);
    selectedEmail = selectedEmail === normalized ? '' : normalized;
  };

  void loadData();
</script>

<Modal
  icon={false}
  size="small"
  title={$t('transfer_ownership')}
  onClose={() => onClose(didChange ? { action: 'refreshAlbum' } : undefined)}
>
  <ModalBody>
    {#if loading}
      <Text size="small" color="muted">{$t('loading')}</Text>
    {:else if hasPendingTransfer && pendingTransfer}
      <div class="rounded-xl border border-gray-300 dark:border-gray-700 p-4">
        <Stack gap={2}>
          <Text class="font-semibold">{$t('transfer_pending_title')}</Text>
          <Text size="small" color="muted"
            >{$t('transfer_pending_description', { values: { email: pendingTransfer.toUser.email } })}</Text
          >
          <div class="flex justify-end">
            <Button
              size="small"
              variant="ghost"
              color="danger"
              leadingIcon={mdiClose}
              disabled={isSubmitting}
              onclick={onCancelTransfer}
            >
              {$t('transfer_cancel')}
            </Button>
          </div>
        </Stack>
      </div>
    {:else}
      <Stack gap={3}>
        <div class="rounded-xl border border-gray-300 dark:border-gray-700 p-4">
          <Stack gap={2}>
            <div class="flex items-start gap-2">
              <Icon icon={mdiSwapHorizontal} size="20" />
              <Text size="small" color="muted">{$t('transfer_ownership_hint')}</Text>
            </div>
            <Text size="small" color="muted">{$t('transfer_warning')}</Text>
          </Stack>
        </div>

        <div class="flex items-center gap-2">
          <Input
            bind:value={emailInput}
            type="email"
            placeholder={$t('enter_email_to_share')}
            onkeydown={(event) => event.key === 'Enter' && !isSubmitting && onSaveEmail()}
          />
          <Button size="small" shape="round" disabled={isSubmitting} onclick={onSaveEmail}>{$t('add')}</Button>
        </div>

        <div>
          <Text size="small" color="muted">{$t('saved_list')}</Text>
          <div
            class="immich-scrollbar mt-2 max-h-60 overflow-y-auto rounded-xl border border-gray-300 dark:border-gray-700"
          >
            {#if sharedEmails.length === 0}
              <div class="p-3">
                <Text size="small" color="muted">{$t('no_shared_emails_yet')}</Text>
              </div>
            {:else}
              <div class="flex flex-col">
                {#each sharedEmails as item (item.email)}
                  {@const normalized = normalizeEmail(item.email)}
                  {@const selected = normalized === selectedEmail}
                  <div
                    class="flex items-center gap-3 border-b border-gray-200 p-3 last:border-b-0 dark:border-gray-800"
                  >
                    <button
                      type="button"
                      class="flex h-8 w-8 items-center justify-center rounded-full border"
                      onclick={() => toggleSelectedEmail(item.email)}
                      disabled={isSubmitting}
                    >
                      {#if selected}
                        <Icon icon={mdiCheck} size="16" />
                      {/if}
                    </button>
                    <div class="grow text-sm">{item.email}</div>
                    <IconButton
                      icon={mdiDeleteOutline}
                      size="small"
                      color="danger"
                      aria-label={$t('remove')}
                      onclick={() => onRemoveEmail(item.email)}
                      disabled={isSubmitting}
                    />
                  </div>
                {/each}
              </div>
            {/if}
          </div>
        </div>

        <Button
          fullWidth
          size="small"
          shape="round"
          leadingIcon={mdiSwapHorizontal}
          disabled={isSubmitting || !selectedEmail}
          onclick={onRequestTransfer}
        >
          {$t('transfer_send')}
        </Button>
      </Stack>
    {/if}
  </ModalBody>
</Modal>
