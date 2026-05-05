<script lang="ts">
  import { uploadManager } from '$lib/managers/upload-manager.svelte';
  import { locale } from '$lib/stores/preferences.store';
  import { interruptedUploadsStore, type InterruptedUploadItem } from '$lib/stores/interrupted-upload';
  import { uploadAssetsStore } from '$lib/stores/upload';
  import { getByteUnitString } from '$lib/utils/byte-units';
  import {
    cancelInterruptedUploadSession,
    removeInterruptedUploadSessionEntry,
    resumeInterruptedUploadSession,
  } from '$lib/utils/file-uploader';
  import { Icon, IconButton, toastManager } from '@immich/ui';
  import { mdiAlertCircle, mdiPlay, mdiRefresh, mdiTrashCanOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { fade, scale } from 'svelte/transition';

  let { hasItems } = interruptedUploadsStore;
  let { isUploading } = uploadAssetsStore;

  let inFlight = $state<Record<string, boolean>>({});

  const pickFile = async () => {
    return await new Promise<File | undefined>((resolve) => {
      const fileSelector = document.createElement('input');
      fileSelector.type = 'file';
      fileSelector.multiple = false;
      fileSelector.accept = uploadManager.getExtensions().join(',');
      fileSelector.addEventListener(
        'change',
        (event: Event) => {
          const target = event.target as HTMLInputElement;
          resolve(target.files?.[0]);
        },
        { passive: true },
      );
      fileSelector.click();
    });
  };

  const handleResume = async (item: InterruptedUploadItem) => {
    if (inFlight[item.cacheKey]) {
      return;
    }

    const file = await pickFile();
    if (!file) {
      return;
    }

    try {
      inFlight[item.cacheKey] = true;
      const task = resumeInterruptedUploadSession({ entry: item, file });

      interruptedUploadsStore.remove(item.cacheKey);

      void task.catch((error) => {
        console.error('Failed to resume interrupted upload', error);
        toastManager.danger($t('errors.unable_to_upload_file'));
        void interruptedUploadsStore.syncFromLocalCache();
      });
    } catch (error) {
      const message = (error as Error | undefined)?.message || $t('errors.unable_to_upload_file');
      toastManager.warning(message);
    } finally {
      inFlight[item.cacheKey] = false;
    }
  };

  const handleCancel = async (item: InterruptedUploadItem) => {
    if (inFlight[item.cacheKey]) {
      return;
    }

    try {
      inFlight[item.cacheKey] = true;
      await cancelInterruptedUploadSession(item.sessionId);
      removeInterruptedUploadSessionEntry(item.cacheKey);
      interruptedUploadsStore.remove(item.cacheKey);
    } catch (error) {
      console.error('Failed to cancel interrupted upload', error);
      toastManager.danger($t('errors.unable_to_upload_file'));
    } finally {
      inFlight[item.cacheKey] = false;
    }
  };
</script>

{#if $hasItems && !$isUploading}
  <div in:fade={{ duration: 250 }} out:fade={{ duration: 250 }} class="fixed bottom-6 end-16 z-30">
    <div
      in:scale={{ duration: 250 }}
      class="w-96 rounded-xl border border-gray-200 dark:border-subtle p-4 text-sm shadow-xs bg-subtle"
    >
      <div class="mb-3 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <Icon icon={mdiAlertCircle} size="22" class="text-warning" />
          <p class="immich-form-label text-xs uppercase tracking-wide">Interrupted uploads</p>
        </div>
        <IconButton
          variant="ghost"
          shape="round"
          color="secondary"
          icon={mdiRefresh}
          size="small"
          aria-label="Refresh interrupted uploads"
          onclick={() => void interruptedUploadsStore.syncFromLocalCache()}
        />
      </div>

      <div class="immich-scrollbar flex max-h-[320px] flex-col gap-2 overflow-y-auto rounded-lg">
        {#each $interruptedUploadsStore as item (item.cacheKey)}
          <div class="rounded-xl border border-gray-300 dark:border-subtle bg-primary/10 p-2 text-xs">
            <div class="mb-1 flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="break-all font-medium">{item.fileName}</p>
                <p class="text-[11px] opacity-80">
                  {getByteUnitString(item.fileSize, $locale)} · {item.uploadedPercent}%
                </p>
              </div>
              <div class="flex items-center gap-1">
                <IconButton
                  variant="ghost"
                  shape="round"
                  color="secondary"
                  icon={mdiPlay}
                  size="small"
                  aria-label={$t('resume')}
                  onclick={() => void handleResume(item)}
                  disabled={inFlight[item.cacheKey]}
                />
                <IconButton
                  variant="ghost"
                  shape="round"
                  color="secondary"
                  icon={mdiTrashCanOutline}
                  size="small"
                  aria-label={$t('cancel')}
                  onclick={() => void handleCancel(item)}
                  disabled={inFlight[item.cacheKey]}
                />
              </div>
            </div>

            <div class="relative mt-1 h-3 w-full rounded-md bg-gray-300 dark:bg-gray-700">
              <div
                class="h-3 rounded-md bg-immich-primary transition-all"
                style={`width: ${item.uploadedPercent}%`}
              ></div>
            </div>
          </div>
        {/each}
      </div>
    </div>
  </div>
{/if}
