<script lang="ts">
  import { invalidate } from '$app/navigation';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import { AppRoute } from '$lib/constants';
  import {
    acceptAlbumTransfer,
    declineAlbumTransfer,
    getAlbumTransferErrorCode,
    getIncomingAlbumTransfers,
    type AlbumTransferDto,
  } from '$lib/services/pizcloud/album-transfer.service';
  import { albumTransferManager, TransferRefreshReason } from '$lib/stores/album-transfer-manager.svelte';
  import { getByteUnitString } from '$lib/utils/byte-units';
  import { handleError } from '$lib/utils/handle-error';
  import { Button, Stack, Text, modalManager, toastManager } from '@immich/ui';
  import { mdiArrowLeft } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let loading = $state(true);
  let isSubmittingById = $state<Record<string, boolean>>({});
  let incomingTransfers = $state<AlbumTransferDto[]>([]);

  const formatSize = (bytes: number) => getByteUnitString(bytes);

  const refreshInbox = async ({ force = false }: { force?: boolean } = {}) => {
    loading = true;

    try {
      await albumTransferManager.refresh({
        ownedAlbumIds: [],
        reason: force ? TransferRefreshReason.PullToRefresh : TransferRefreshReason.PageOpen,
        force,
        includeIncoming: true,
      });
      incomingTransfers = [...albumTransferManager.incomingTransfers];
    } catch {
      // Fallback read keeps inbox usable even if manager refresh fails unexpectedly.
      incomingTransfers = await getIncomingAlbumTransfers();
      albumTransferManager.incomingTransfers = incomingTransfers;
    } finally {
      loading = false;
    }
  };

  const setSubmitting = (transferId: string, value: boolean) => {
    isSubmittingById = { ...isSubmittingById, [transferId]: value };
  };

  const onAccept = async (transfer: AlbumTransferDto) => {
    const confirmed = await modalManager.showDialog({
      icon: false,
      title: $t('transfer_accept_title'),
      prompt: $t('transfer_accept_confirm'),
      confirmText: $t('confirm'),
    });

    if (!confirmed) {
      return;
    }

    try {
      setSubmitting(transfer.id, true);
      await acceptAlbumTransfer(transfer.id);
      toastManager.success($t('transfer_accept_success'));
      await refreshInbox({ force: true });
      await invalidate('app:albums');
    } catch (error) {
      const code = getAlbumTransferErrorCode(error);

      if (code.includes('insufficient_quota')) {
        toastManager.info($t('transfer_insufficient_quota'));
        return;
      }

      if (code.includes('asset_conflict')) {
        toastManager.info($t('transfer_asset_conflict'));
        return;
      }

      handleError(error, $t('transfer_request_failed'));
    } finally {
      setSubmitting(transfer.id, false);
    }
  };

  const onDecline = async (transfer: AlbumTransferDto) => {
    try {
      setSubmitting(transfer.id, true);
      await declineAlbumTransfer(transfer.id);
      toastManager.success($t('transfer_decline_success'));
      await refreshInbox({ force: true });
      await invalidate('app:albums');
    } catch (error) {
      handleError(error, $t('transfer_request_failed'));
    } finally {
      setSubmitting(transfer.id, false);
    }
  };

  void refreshInbox();
</script>

<UserPageLayout title={data.meta.title}>
  {#snippet buttons()}
    <Button href={AppRoute.ALBUMS} leadingIcon={mdiArrowLeft} size="small" variant="ghost" color="secondary">
      {$t('albums')}
    </Button>
  {/snippet}

  <div class="mx-auto w-full max-w-3xl py-4">
    {#if loading}
      <Text size="small" color="muted">{$t('loading')}</Text>
    {:else if incomingTransfers.length === 0}
      <div class="rounded-2xl border border-gray-200 bg-gray-50 p-8 dark:border-gray-800 dark:bg-immich-dark-gray">
        <Text>{$t('transfer_inbox_empty')}</Text>
      </div>
    {:else}
      <div class="flex flex-col gap-3">
        {#each incomingTransfers as transfer (transfer.id)}
          {@const isSubmitting = Boolean(isSubmittingById[transfer.id])}
          <div class="rounded-2xl border border-gray-200 bg-gray-50 p-4 dark:border-gray-800 dark:bg-immich-dark-gray">
            <Stack gap={2}>
              <Text class="font-semibold">{transfer.albumName}</Text>
              <Text size="small" color="muted"
                >{$t('transfer_from_user', { values: { email: transfer.fromUser.email } })}</Text
              >
              <Text size="small" color="muted"
                >{$t('transfer_album_size', {
                  values: { capacity: formatSize(transfer.totalBytes), count: String(transfer.assetCount) },
                })}</Text
              >

              <div class="flex justify-end gap-2 pt-1">
                <Button
                  size="small"
                  variant="ghost"
                  color="secondary"
                  disabled={isSubmitting}
                  onclick={() => onDecline(transfer)}
                >
                  {$t('transfer_decline')}
                </Button>
                <Button size="small" variant="filled" disabled={isSubmitting} onclick={() => onAccept(transfer)}>
                  {$t('transfer_accept')}
                </Button>
              </div>
            </Stack>
          </div>
        {/each}
      </div>
    {/if}
  </div>
</UserPageLayout>
