import { user } from '$lib/stores/user.store';
import {
  getInterruptedUploadSessionStatus,
  listInterruptedUploadSessionEntries,
  removeInterruptedUploadSessionEntry,
  type InterruptedUploadSessionEntry,
} from '$lib/utils/file-uploader';
import { derived, get, writable } from 'svelte/store';

export type InterruptedUploadItem = InterruptedUploadSessionEntry & {
  status: 'active' | 'completed';
  chunkSize: number;
  totalChunks: number;
  uploadedChunks: number[];
  uploadedPercent: number;
};

function createInterruptedUploadStore() {
  const items = writable<InterruptedUploadItem[]>([]);

  const { subscribe } = items;
  const hasItems = derived(items, (value) => value.length > 0);

  const reset = () => {
    items.set([]);
  };

  const remove = (cacheKey: string) => {
    items.update((value) => value.filter((item) => item.cacheKey !== cacheKey));
  };

  const syncFromLocalCache = async () => {
    if (!get(user)) {
      reset();
      return;
    }

    const cacheEntries = listInterruptedUploadSessionEntries();
    if (cacheEntries.length === 0) {
      reset();
      return;
    }

    const next: InterruptedUploadItem[] = [];

    for (const entry of cacheEntries) {
      try {
        const status = await getInterruptedUploadSessionStatus(entry.sessionId);
        const uploadedPercent =
          status.totalChunks > 0 ? Math.floor((status.uploadedChunks.length / status.totalChunks) * 100) : 0;

        next.push({
          ...entry,
          status: status.status,
          chunkSize: status.chunkSize,
          totalChunks: status.totalChunks,
          uploadedChunks: status.uploadedChunks,
          uploadedPercent,
        });
      } catch (error) {
        const status = (error as { status?: number } | undefined)?.status;

        if (status === 404) {
          removeInterruptedUploadSessionEntry(entry.cacheKey);
        }
      }
    }

    items.set(next);
  };

  return {
    hasItems,
    syncFromLocalCache,
    reset,
    remove,
    subscribe,
  };
}

export const interruptedUploadsStore = createInterruptedUploadStore();
