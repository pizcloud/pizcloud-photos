import {
  getAlbumTransfer,
  getIncomingAlbumTransfers,
  isPendingTransfer,
  type AlbumTransferDto,
} from '$lib/services/pizcloud/album-transfer.service';

export enum TransferRefreshReason {
  TabEnter = 'tab_enter',
  AppResume = 'app_resume',
  PageOpen = 'page_open',
  PullToRefresh = 'pull_to_refresh',
  LocalMutation = 'local_mutation',
}

type RefreshOptions = {
  ownedAlbumIds?: string[];
  reason: TransferRefreshReason;
  force?: boolean;
  includeIncoming?: boolean;
};

class AlbumTransferManager {
  incomingTransfers = $state<AlbumTransferDto[]>([]);
  pendingTransferByAlbumId = $state<Record<string, AlbumTransferDto | null>>({});

  #lastRefreshAt: Date | null = null;
  #refreshInFlight: Promise<void> | null = null;

  async refresh(options: RefreshOptions) {
    const { ownedAlbumIds = [], reason, force = false, includeIncoming = true } = options;

    const inFlight = this.#refreshInFlight;
    if (inFlight) {
      await inFlight;
      return;
    }

    const maxStaleness = 60_000;
    const minInterval = this.#getMinInterval(reason);
    const now = Date.now();
    const elapsed = this.#lastRefreshAt ? now - this.#lastRefreshAt.getTime() : maxStaleness;
    const shouldThrottle = !force && elapsed < minInterval && elapsed < maxStaleness;

    if (shouldThrottle) {
      return;
    }

    const refreshTask = this.#refreshImpl({ ownedAlbumIds, includeIncoming });
    this.#refreshInFlight = refreshTask;

    try {
      await refreshTask;
      this.#lastRefreshAt = new Date();
    } finally {
      if (this.#refreshInFlight === refreshTask) {
        this.#refreshInFlight = null;
      }
    }
  }

  setTransfer(albumId: string, transfer: AlbumTransferDto | null) {
    this.pendingTransferByAlbumId = {
      ...this.pendingTransferByAlbumId,
      [albumId]: isPendingTransfer(transfer) ? transfer : null,
    };
  }

  removeAlbum(albumId: string) {
    if (!(albumId in this.pendingTransferByAlbumId)) {
      return;
    }

    const next = { ...this.pendingTransferByAlbumId };
    delete next[albumId];
    this.pendingTransferByAlbumId = next;
  }

  clear() {
    this.incomingTransfers = [];
    this.pendingTransferByAlbumId = {};
    this.#lastRefreshAt = null;
  }

  async #refreshImpl(options: { ownedAlbumIds: string[]; includeIncoming: boolean }) {
    const { ownedAlbumIds, includeIncoming } = options;

    const [incoming, transferEntries] = await Promise.all([
      includeIncoming ? getIncomingAlbumTransfers() : Promise.resolve(this.incomingTransfers),
      Promise.all(
        ownedAlbumIds.map(async (albumId) => {
          try {
            const transfer = await getAlbumTransfer(albumId);
            return [albumId, isPendingTransfer(transfer) ? transfer : null] as const;
          } catch {
            return [albumId, null] as const;
          }
        }),
      ),
    ]);

    if (includeIncoming) {
      this.incomingTransfers = incoming;
    }

    const nextPendingByAlbumId: Record<string, AlbumTransferDto | null> = {};
    for (const [albumId, transfer] of transferEntries) {
      nextPendingByAlbumId[albumId] = transfer;
    }

    this.pendingTransferByAlbumId = {
      ...this.pendingTransferByAlbumId,
      ...nextPendingByAlbumId,
    };
  }

  #getMinInterval(reason: TransferRefreshReason): number {
    switch (reason) {
      case TransferRefreshReason.TabEnter:
      case TransferRefreshReason.AppResume:
      case TransferRefreshReason.PageOpen:
        return 10_000;
      case TransferRefreshReason.PullToRefresh:
      case TransferRefreshReason.LocalMutation:
        return 0;
      default:
        return 10_000;
    }
  }
}

export const albumTransferManager = new AlbumTransferManager();
