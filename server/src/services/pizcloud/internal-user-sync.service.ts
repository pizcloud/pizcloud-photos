import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { SyncEntityType } from 'src/enum';
import { AssetRepository, InternalAssetCursor } from 'src/repositories/asset.repository';
import { SessionRepository } from 'src/repositories/session.repository';
import { SyncCheckpointRepository } from 'src/repositories/sync-checkpoint.repository';
import { UserRepository } from 'src/repositories/user.repository';
import { BillingService } from 'src/services/pizcloud/billing.service';
import { getPreferences } from 'src/utils/preferences';
import { fromAck } from 'src/utils/sync';

const FULL_SYNC_STALE_MS = 30 * 24 * 60 * 60 * 1000;
const BYTES_IN_GIB = 1024 ** 3;
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const toIso = (value: Date | null | undefined) => value?.toISOString() ?? null;

const isUuid = (value: string | undefined): value is string => !!value && UUID_REGEX.test(value);

const getUuidV7Date = (updateId: string | undefined): Date | null => {
  if (!isUuid(updateId)) {
    return null;
  }

  const milliseconds = Number.parseInt(updateId.replaceAll('-', '').slice(0, 12), 16);
  if (!Number.isFinite(milliseconds)) {
    return null;
  }

  return new Date(milliseconds);
};

const mapAssetCursor = (asset: InternalAssetCursor | null | undefined) =>
  asset
    ? {
      id: asset.id,
      updateId: asset.updateId,
      originalFileName: asset.originalFileName,
      deviceId: asset.deviceId,
      deviceAssetId: asset.deviceAssetId,
      createdAt: asset.createdAt.toISOString(),
      updatedAt: asset.updatedAt.toISOString(),
      fileCreatedAt: asset.fileCreatedAt.toISOString(),
      fileModifiedAt: asset.fileModifiedAt.toISOString(),
      deletedAt: toIso(asset.deletedAt),
      status: asset.status,
      visibility: asset.visibility,
    }
    : null;

type UsageState = 'ok' | 'warn' | 'critical' | 'blocked';

@Injectable()
export class InternalUserSyncService {
  constructor(
    private readonly userRepository: UserRepository,
    private readonly assetRepository: AssetRepository,
    private readonly sessionRepository: SessionRepository,
    private readonly syncCheckpointRepository: SyncCheckpointRepository,
    private readonly billingService: BillingService,
  ) { }

  async getUserSyncOverview({ email, userId }: { email?: string; userId?: string }) {
    const normalizedEmail = email?.trim().toLowerCase();
    if (!normalizedEmail && !userId) {
      throw new BadRequestException('Query param "email" or "userId" is required');
    }

    const user = userId
      ? await this.userRepository.get(userId, { withDeleted: true })
      : await this.userRepository.getByEmail(normalizedEmail!);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const [assetSummary, sessions] = await Promise.all([
      this.assetRepository.getInternalSyncSummary(user.id),
      this.sessionRepository.getByUserId(user.id),
    ]);

    const checkpoints = await this.syncCheckpointRepository.getBySessionIds(sessions.map((session) => session.id));
    const checkpointsBySession = new Map<string, typeof checkpoints>();
    for (const checkpoint of checkpoints) {
      const existing = checkpointsBySession.get(checkpoint.sessionId) ?? [];
      existing.push(checkpoint);
      checkpointsBySession.set(checkpoint.sessionId, existing);
    }

    const sessionSummaries = await Promise.all(
      sessions.map(async (session) => {
        const checkpointRows = checkpointsBySession.get(session.id) ?? [];
        const checkpointByType = new Map(checkpointRows.map((checkpoint) => [checkpoint.type, checkpoint]));
        const completeCheckpoint = checkpointByType.get(SyncEntityType.SyncCompleteV1);
        const completeAck = completeCheckpoint ? fromAck(completeCheckpoint.ack) : undefined;
        const completeAt = getUuidV7Date(completeAck?.updateId);
        const needsFullSync = completeAt ? completeAt.getTime() < Date.now() - FULL_SYNC_STALE_MS : false;

        const assetCheckpoint = checkpointByType.get(SyncEntityType.AssetV1);
        const assetAck = assetCheckpoint ? fromAck(assetCheckpoint.ack) : undefined;
        const assetDeleteCheckpoint = checkpointByType.get(SyncEntityType.AssetDeleteV1);
        const assetDeleteAck = assetDeleteCheckpoint ? fromAck(assetDeleteCheckpoint.ack) : undefined;

        const [pendingServerChangesSinceComplete, lastAssetSynced] = await Promise.all([
          isUuid(completeAck?.updateId)
            ? this.assetRepository.countSyncAssetChangesAfter(user.id, completeAck.updateId)
            : Promise.resolve(null),
          isUuid(assetAck?.updateId)
            ? this.assetRepository.getLatestOwnedAssetAtOrBeforeUpdateId(user.id, assetAck.updateId)
            : Promise.resolve(null),
        ]);

        return {
          sessionId: session.id,
          deviceType: session.deviceType,
          deviceOS: session.deviceOS,
          appVersion: session.appVersion,
          updatedAt: session.updatedAt.toISOString(),
          expiresAt: toIso(session.expiresAt),
          isPendingSyncReset: session.isPendingSyncReset,
          checkpointsCount: checkpointRows.length,
          checkpointTypes: checkpointRows.map((item) => item.type),
          checkpointHeads: {
            syncComplete: isUuid(completeAck?.updateId) ? completeAck.updateId : null,
            asset: isUuid(assetAck?.updateId) ? assetAck.updateId : null,
            assetDelete: isUuid(assetDeleteAck?.updateId) ? assetDeleteAck.updateId : null,
          },
          lastSyncCompletedAt: toIso(completeAt),
          lastSyncCheckpointUpdatedAt: toIso(completeCheckpoint?.updatedAt),
          needsFullSync,
          pendingServerChangesSinceComplete: pendingServerChangesSinceComplete
            ? {
              ...pendingServerChangesSinceComplete,
              totalChanges:
                pendingServerChangesSinceComplete.upsertedAssets + pendingServerChangesSinceComplete.deletedAssets,
            }
            : null,
          lastAssetSynced: mapAssetCursor(lastAssetSynced),
        };
      }),
    );

    let latestSyncSession: (typeof sessionSummaries)[number] | null = null;
    let latestSyncTimestamp = -1;
    for (const session of sessionSummaries) {
      if (!session.lastSyncCompletedAt) {
        continue;
      }

      const sessionTimestamp = Date.parse(session.lastSyncCompletedAt);
      if (!Number.isFinite(sessionTimestamp)) {
        continue;
      }

      if (sessionTimestamp > latestSyncTimestamp) {
        latestSyncTimestamp = sessionTimestamp;
        latestSyncSession = session;
      }
    }

    const usage = this.mapUsage(user.quotaUsageInBytes ?? 0, user.quotaSizeInBytes);

    return {
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        status: user.status,
        isAdmin: user.isAdmin,
        createdAt: user.createdAt.toISOString(),
        updatedAt: user.updatedAt.toISOString(),
        deletedAt: toIso(user.deletedAt),
        storageLabel: user.storageLabel,
        oauthId: user.oauthId,
      },
      quota: usage,
      preferences: getPreferences(user.metadata ?? []),
      entitlement: this.billingService.getEntitlement(user.id),
      syncControl: {
        serverManagedEnabledSetting: null,
        note: '',
      },
      assets: {
        totalAssets: assetSummary.totalAssets,
        activeAssets: assetSummary.activeAssets,
        trashedAssets: assetSummary.trashedAssets,
        pendingHardDeleteAssets: assetSummary.pendingHardDeleteAssets,
        offlineAssets: assetSummary.offlineAssets,
        externalAssets: assetSummary.externalAssets,
        activeByType: {
          image: assetSummary.activeImageAssets,
          video: assetSummary.activeVideoAssets,
          audio: assetSummary.activeAudioAssets,
          other: assetSummary.activeOtherAssets,
        },
        activeByVisibility: {
          timeline: assetSummary.activeTimelineAssets,
          archive: assetSummary.activeArchiveAssets,
          hidden: assetSummary.activeHiddenAssets,
          locked: assetSummary.activeLockedAssets,
        },
        latestByCreatedAt: mapAssetCursor(assetSummary.latestByCreatedAt),
        latestByUpdateId: mapAssetCursor(assetSummary.latestByUpdateId),
      },
      sync: {
        sessionCount: sessionSummaries.length,
        sessionsPendingSyncReset: sessionSummaries.filter((item) => item.isPendingSyncReset).length,
        sessionsWithCheckpoints: sessionSummaries.filter((item) => item.checkpointsCount > 0).length,
        sessionsNeedingFullSync: sessionSummaries.filter((item) => item.needsFullSync).map((item) => item.sessionId),
        lastSyncCompletedAt: latestSyncSession?.lastSyncCompletedAt ?? null,
        latestSessionId: latestSyncSession?.sessionId ?? null,
        estimatedPendingServerChangesFromLatestSession: latestSyncSession?.pendingServerChangesSinceComplete ?? null,
        sessions: sessionSummaries,
      },
    };
  }

  private mapUsage(usageBytes: number, limitBytes: number | null) {
    const percent = limitBytes && limitBytes > 0 ? Math.min(100, Math.round((usageBytes / limitBytes) * 100)) : 0;

    let state: UsageState = 'ok';
    if (limitBytes && limitBytes > 0) {
      if (percent >= 100) {
        state = 'blocked';
      } else if (percent >= 90) {
        state = 'critical';
      } else if (percent >= 80) {
        state = 'warn';
      }
    }

    return {
      usedBytes: usageBytes,
      limitBytes,
      usedGiB: Number((usageBytes / BYTES_IN_GIB).toFixed(2)),
      limitGiB: limitBytes == null ? null : Number((limitBytes / BYTES_IN_GIB).toFixed(2)),
      percent,
      state,
    };
  }
}
