// server/src/services/billing.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto';
import { UserAdminService } from 'src/services/user-admin.service';

export type Period = 'monthly' | 'yearly';

export type EntitlementStatus =
  | 'active'
  | 'in_grace_period'
  | 'on_hold'
  | 'paused'
  | 'canceled_pending_expiry'
  | 'expired'
  | 'revoked'
  | 'pending'
  | 'pending_purchase_canceled';

export type EntitlementWebhookBody = {
  userId: string;
  email: string;
  productId: string;
  planCode: string;
  storageLimitGb: number;
  mlTier?: 'free' | 'basic' | 'pro1' | 'pro2' | 'pro3' | 'premium';
  seats?: number;
  shareEnabled?: boolean;
  signature: string;       // HMAC-SHA256(JSON(payload_without_signature))

  // Optional fields for normalized entitlement snapshots from external billing service.
  schemaVersion?: 2;
  eventId?: string;
  eventTimeMs?: number;
  source?: 'google_play_rtdn' | 'app_store_server_notification';
  platform?: 'android' | 'ios';
  entitlementStatus?: EntitlementStatus;
  autoRenewEnabled?: boolean;
  expiresAtMs?: number;
  cancelReason?: 'user' | 'system' | 'developer' | 'replacement' | 'unknown';
  providerNotificationType?: number;
  providerSubscriptionState?: string;
  purchaseToken?: string;
  linkedPurchaseToken?: string;
};

type MlTier = 'free' | 'basic' | 'pro1' | 'pro2' | 'pro3' | 'premium';

type ProductInfo = {
  planCode: string;
  storageLimitGb: number;
  mlTier: MlTier;
  seats: number;
  shareEnabled: boolean;
  period: Period;
};

type EntitlementData = {
  userId: string;
  userEmail?: string;
  productId: string;
  planCode: string;
  storageLimitGb: number;
  mlTier?: MlTier;
  seats?: number;
  shareEnabled?: boolean;
  period?: Period;
  expiresAtMs?: number;
  purchaseToken?: string;
  linkedPurchaseToken?: string;
  schemaVersion?: 2;
  eventId?: string;
  eventTimeMs?: number;
  source?: 'google_play_rtdn' | 'app_store_server_notification';
  platform?: 'android' | 'ios';
  entitlementStatus?: EntitlementStatus;
  autoRenewEnabled?: boolean;
  cancelReason?: 'user' | 'system' | 'developer' | 'replacement' | 'unknown';
  providerNotificationType?: number;
  providerSubscriptionState?: string;
};

const PRODUCT_MAP: Record<string, ProductInfo> = {
  // 50 GB
  'storage_50gb_monthly': { planCode: '50GB', storageLimitGb: 50, mlTier: 'basic', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_50gb_yearly': { planCode: '50GB', storageLimitGb: 50, mlTier: 'basic', seats: 1, shareEnabled: true, period: 'yearly' },

  // 100 GB
  'storage_100gb_monthly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro1', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_100gb_yearly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro1', seats: 1, shareEnabled: true, period: 'yearly' },

  // 500 GB
  'storage_500gb_monthly': { planCode: '500GB', storageLimitGb: 500, mlTier: 'pro2', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_500gb_yearly': { planCode: '500GB', storageLimitGb: 500, mlTier: 'pro2', seats: 1, shareEnabled: true, period: 'yearly' },

  // 1 TB
  'storage_1tb_monthly': { planCode: '1TB', storageLimitGb: 1000, mlTier: 'pro3', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_1tb_yearly': { planCode: '1TB', storageLimitGb: 1000, mlTier: 'pro3', seats: 1, shareEnabled: true, period: 'yearly' },

  // 2 TB
  'storage_2tb_monthly': { planCode: '2TB', storageLimitGb: 2000, mlTier: 'premium', seats: 5, shareEnabled: true, period: 'monthly' },
  'storage_2tb_yearly': { planCode: '2TB', storageLimitGb: 2000, mlTier: 'premium', seats: 5, shareEnabled: true, period: 'yearly' },
};


@Injectable()
export class BillingService {
  private readonly logger = new Logger(BillingService.name);
  private static readonly RECENT_EVENT_IDS_LIMIT = 40;

  private readonly entitlements = new Map<string, EntitlementData>();

  private readonly purchaseTokenToUser = new Map<
    string,
    { userId: string; userEmail?: string; productId: string }
  >();
  private readonly entitlementEventMeta = new Map<
    string,
    {
      lastEventTimeMs?: number;
      recentEventIds: string[];
    }
  >();

  constructor(private readonly userAdmin: UserAdminService,) { }

  private computeQuotaBytes(storageLimitGb: number): number | null {
    const limitGiB = Number.isFinite(storageLimitGb)
      ? Math.max(0, Math.floor(storageLimitGb))
      : 0;

    if (limitGiB === 0) {
      return 0;
    }
    return limitGiB * 1024 ** 3;
  }

  private resolveStorageLimitGb(body: EntitlementWebhookBody): number {
    const direct = Number(body.storageLimitGb);
    if (Number.isFinite(direct)) {
      return Math.max(0, Math.floor(direct));
    }

    // Keep a safe fallback for malformed payloads: if productId is known, use mapped size.
    const mapped = PRODUCT_MAP[body.productId]?.storageLimitGb;
    if (Number.isFinite(mapped)) {
      return Math.max(0, Math.floor(mapped));
    }

    this.logger.warn(
      `Entitlement webhook: invalid storageLimitGb for email=${body.email}, productId=${body.productId}. Fallback to 0.`,
    );
    return 0;
  }

  private parseEventId(input?: string): string | undefined {
    const eventId = input?.trim();
    return eventId || undefined;
  }

  private parseEventTimeMs(input?: number): number | undefined {
    const value = typeof input === 'number' ? input : Number.NaN;
    if (!Number.isFinite(value)) {
      return undefined;
    }

    const normalized = Math.floor(value);
    return normalized > 0 ? normalized : undefined;
  }

  private shouldSkipEvent(resolvedUserId: string, body: EntitlementWebhookBody): boolean {
    const current = this.entitlementEventMeta.get(resolvedUserId);
    if (current == null) {
      return false;
    }

    const eventId = this.parseEventId(body.eventId);
    if (eventId && current.recentEventIds.includes(eventId)) {
      this.logger.log(`Entitlement webhook: duplicate event ignored userId=${resolvedUserId}, eventId=${eventId}`);
      return true;
    }

    const eventTimeMs = this.parseEventTimeMs(body.eventTimeMs);
    if (eventTimeMs != null && current.lastEventTimeMs != null && eventTimeMs < current.lastEventTimeMs) {
      this.logger.warn(
        `Entitlement webhook: stale event ignored userId=${resolvedUserId}, eventTimeMs=${eventTimeMs}, lastEventTimeMs=${current.lastEventTimeMs}`,
      );
      return true;
    }

    return false;
  }

  private isCancellationLikeStatus(status?: EntitlementStatus): boolean {
    if (status == null) {
      return false;
    }

    return (
      status === 'canceled_pending_expiry' ||
      status === 'expired' ||
      status === 'revoked' ||
      status === 'pending_purchase_canceled'
    );
  }

  private shouldSkipQuotaDowngradeFromReplacedToken(
    resolvedUserId: string,
    body: EntitlementWebhookBody,
    resolvedStorageLimitGb: number,
  ): boolean {
    const current = this.entitlements.get(resolvedUserId);
    if (current == null) {
      return false;
    }

    const currentToken = current.purchaseToken?.trim();
    const incomingToken = body.purchaseToken?.trim();
    if (!currentToken || !incomingToken || currentToken === incomingToken) {
      return false;
    }

    if (!this.isCancellationLikeStatus(body.entitlementStatus)) {
      return false;
    }

    if (resolvedStorageLimitGb >= current.storageLimitGb) {
      return false;
    }

    this.logger.warn(
      `Entitlement webhook: skip quota downgrade from replaced token userId=${resolvedUserId}, ` +
      `incomingToken=${incomingToken}, currentToken=${currentToken}, incomingStatus=${body.entitlementStatus}, ` +
      `incomingLimitGb=${resolvedStorageLimitGb}, currentLimitGb=${current.storageLimitGb}`,
    );
    return true;
  }

  private recordEventMeta(resolvedUserId: string, body: EntitlementWebhookBody): void {
    const previous = this.entitlementEventMeta.get(resolvedUserId);
    const previousIds = previous?.recentEventIds ?? [];
    const recentEventIds = [...previousIds];

    const eventId = this.parseEventId(body.eventId);
    if (eventId && !recentEventIds.includes(eventId)) {
      recentEventIds.push(eventId);
      if (recentEventIds.length > BillingService.RECENT_EVENT_IDS_LIMIT) {
        recentEventIds.splice(0, recentEventIds.length - BillingService.RECENT_EVENT_IDS_LIMIT);
      }
    }

    const eventTimeMs = this.parseEventTimeMs(body.eventTimeMs);
    let lastEventTimeMs = previous?.lastEventTimeMs;
    if (eventTimeMs != null) {
      lastEventTimeMs = Math.max(previous?.lastEventTimeMs ?? eventTimeMs, eventTimeMs);
    }

    this.entitlementEventMeta.set(resolvedUserId, {
      lastEventTimeMs,
      recentEventIds,
    });
  }

  async getUsage(auth: AuthDto) {
    const me = await this.userAdmin.get(auth, auth.user.id);
    // const stats = await this.userAdmin.getStatistics(auth, auth.user.id, {} as any);

    const usage = me.quotaUsageInBytes ?? 0;
    const limit = me.quotaSizeInBytes; // null = unlimited

    const percent = limit && limit > 0 ? Math.min(100, Math.round((usage / limit) * 100)) : 0;

    let state: 'ok' | 'warn' | 'critical' | 'blocked' = 'ok';
    if (limit && limit > 0) {
      if (percent >= 100) {
        state = 'blocked';
      } else if (percent >= 90) {
        state = 'critical';
      } else if (percent >= 80) {
        state = 'warn';
      }
    }

    const limitGb = limit == null ? null : (limit / (1024 ** 3)).toFixed(0);

    return {
      used_bytes: usage,
      limit_bytes: limit, // number | null
      used_gb: (usage / (1024 ** 3)).toFixed(2),
      limit_gb: limitGb,
      percent,
      state,
    };
  }

  async getUsageByUserEmail(email: string) {
    const user = await this.userAdmin.getByEmail(email);

    const usage = user?.quotaUsageInBytes ?? 0;
    const limit = user?.quotaSizeInBytes; // null = unlimited

    const percent = limit && limit > 0 ? Math.min(100, Math.round((usage / limit) * 100)) : 0;

    let state: 'ok' | 'warn' | 'critical' | 'blocked' = 'ok';
    if (limit && limit > 0) {
      if (percent >= 100) {
        state = 'blocked';
      } else if (percent >= 90) {
        state = 'critical';
      } else if (percent >= 80) {
        state = 'warn';
      }
    }

    const limitGb = limit == null ? null : (limit / (1024 ** 3)).toFixed(0);

    return {
      used_bytes: usage,
      limit_bytes: limit, // number | null
      used_gb: (usage / (1024 ** 3)).toFixed(2),
      limit_gb: limitGb,
      percent,
      state,
    };
  }

  getEntitlement(userId: string): EntitlementData | null {
    return this.entitlements.get(userId) ?? null;
  }

  async handleEntitlementWebhook(body: EntitlementWebhookBody,): Promise<{ ok: true }> {

    const { ...payloadWithoutSignature } = body;

    const resolvedStorageLimitGb = this.resolveStorageLimitGb(body);
    const quotaSizeInBytes = this.computeQuotaBytes(resolvedStorageLimitGb);
    // await this.userAdmin.updateUserQuota(body.userId, quotaSizeInBytes);

    const user = await this.userAdmin.getByEmail(body.email);
    if (!user) {
      this.logger.warn(`Entitlement webhook: user not found for email=${body.email}`);
      return { ok: true };
    }

    const resolvedUserId = user.id;

    if (this.shouldSkipEvent(resolvedUserId, body)) {
      return { ok: true };
    }

    if (this.shouldSkipQuotaDowngradeFromReplacedToken(resolvedUserId, body, resolvedStorageLimitGb)) {
      this.recordEventMeta(resolvedUserId, body);
      return { ok: true };
    }

    await this.userAdmin.updateUserQuota(resolvedUserId, quotaSizeInBytes);

    const entitlement: EntitlementData = {
      ...payloadWithoutSignature,
      userId: resolvedUserId,
      userEmail: body.email,
      storageLimitGb: resolvedStorageLimitGb,
    };

    this.entitlements.set(resolvedUserId, entitlement);

    if (body.purchaseToken) {
      this.purchaseTokenToUser.set(body.purchaseToken, {
        userId: resolvedUserId,
        userEmail: body.email,
        productId: body.productId,
      });
    }

    this.recordEventMeta(resolvedUserId, body);

    return { ok: true };
  }
}
