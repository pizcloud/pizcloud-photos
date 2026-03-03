import { Injectable, Logger } from '@nestjs/common';
import { Insertable } from 'kysely';
import { DEFAULT_FREE_TIER_QUOTA_BYTES } from 'src/constants';
import { OnEvent, OnJob } from 'src/decorators';
import { AuthDto } from 'src/dtos/auth.dto';
import { ImmichWorker, JobName, QueueName } from 'src/enum';
import {
  BillingSubscriptionRepository,
  BillingSubscriptionStateRecord,
} from 'src/repositories/billing-subscription.repository';
import { JobRepository } from 'src/repositories/job.repository';
import { BillingSubscriptionStateTable } from 'src/schema/tables/billing-subscription-state.table';
import { UserAdminService } from 'src/services/user-admin.service';

export type Period = 'monthly' | 'yearly';
type EntitlementEventType =
  | 'PURCHASED'
  | 'RENEWED'
  | 'RECOVERED'
  | 'CANCELED'
  | 'EXPIRED'
  | 'REVOKED'
  | 'REFUNDED'
  | 'ON_HOLD'
  | 'GRACE_PERIOD';

type MlTier = 'free' | 'basic' | 'pro1' | 'pro2' | 'pro3' | 'premium';

type ProductInfo = {
  planCode: string;
  storageLimitGb: number;
  mlTier: MlTier;
  seats: number;
  shareEnabled: boolean;
  period: Period;
};

export type EntitlementWebhookBody = {
  providerEventId?: string;
  eventType?: string;
  eventTimeMs?: number | string;
  userId?: string;
  email?: string;
  userEmail?: string;
  platform?: 'android' | 'ios' | string;
  productId: string;
  planCode?: string;
  storageLimitGb?: number;
  mlTier?: MlTier;
  seats?: number;
  shareEnabled?: boolean;
  period?: Period;
  expiresAtMs?: number | string;
  purchaseToken?: string;
  cancelAtPeriodEnd?: boolean;
  signature?: string;
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
  status?: string;
  cancelAtPeriodEnd?: boolean;
  expiresAtMs?: number;
  purchaseToken?: string;
};

type SubscriptionStatusData = {
  status: string;
  productId: string;
  planCode: string;
  storageLimitGb: number;
  period?: Period;
  expiresAtMs?: number;
  cancelAtPeriodEnd: boolean;
  effectiveQuotaGb: number;
  freeTierQuotaGb: number;
  willDowngradeAtMs?: number;
  serverNowMs: number;
};

type NormalizedEntitlementEvent = {
  providerEventId: string;
  eventType: EntitlementEventType;
  eventTimeMs: number;
  userEmail: string;
  platform: string;
  productId: string;
  planCode: string;
  storageLimitGb: number;
  mlTier?: MlTier;
  seats?: number;
  shareEnabled?: boolean;
  period?: Period;
  expiresAtMs: number | null;
  purchaseToken: string | null;
  cancelAtPeriodEnd: boolean;
  rawPayload: Record<string, unknown>;
};

const PRODUCT_MAP: Record<string, ProductInfo> = {
  // 50 GB
  storage_50gb_monthly: {
    planCode: '50GB',
    storageLimitGb: 50,
    mlTier: 'basic',
    seats: 1,
    shareEnabled: true,
    period: 'monthly',
  },
  storage_50gb_yearly: {
    planCode: '50GB',
    storageLimitGb: 50,
    mlTier: 'basic',
    seats: 1,
    shareEnabled: true,
    period: 'yearly',
  },

  // 100 GB
  storage_100g_monthly: {
    planCode: '100G',
    storageLimitGb: 100,
    mlTier: 'pro1',
    seats: 1,
    shareEnabled: true,
    period: 'monthly',
  },
  storage_100g_yearly: {
    planCode: '100G',
    storageLimitGb: 100,
    mlTier: 'pro1',
    seats: 1,
    shareEnabled: true,
    period: 'yearly',
  },

  // 500 GB
  storage_500gb_monthly: {
    planCode: '500GB',
    storageLimitGb: 500,
    mlTier: 'pro2',
    seats: 1,
    shareEnabled: true,
    period: 'monthly',
  },
  storage_500gb_yearly: {
    planCode: '500GB',
    storageLimitGb: 500,
    mlTier: 'pro2',
    seats: 1,
    shareEnabled: true,
    period: 'yearly',
  },

  // 1 TB
  storage_1tb_monthly: {
    planCode: '1TB',
    storageLimitGb: 1000,
    mlTier: 'pro3',
    seats: 1,
    shareEnabled: true,
    period: 'monthly',
  },
  storage_1tb_yearly: {
    planCode: '1TB',
    storageLimitGb: 1000,
    mlTier: 'pro3',
    seats: 1,
    shareEnabled: true,
    period: 'yearly',
  },

  // 2 TB
  storage_2tb_monthly: {
    planCode: '2TB',
    storageLimitGb: 2000,
    mlTier: 'premium',
    seats: 5,
    shareEnabled: true,
    period: 'monthly',
  },
  storage_2tb_yearly: {
    planCode: '2TB',
    storageLimitGb: 2000,
    mlTier: 'premium',
    seats: 5,
    shareEnabled: true,
    period: 'yearly',
  },
};

@Injectable()
export class BillingService {
  private readonly logger = new Logger(BillingService.name);

  constructor(
    private readonly userAdmin: UserAdminService,
    private readonly subscriptionRepository: BillingSubscriptionRepository,
    private readonly jobRepository: JobRepository,
  ) {}

  private computeQuotaBytes(storageLimitGb: number): number | null {
    const limitGiB = Number.isFinite(storageLimitGb) ? Math.max(0, Math.floor(storageLimitGb)) : 0;
    return limitGiB * 1024 ** 3;
  }

  private parseMs(value: number | string | null | undefined): number | null {
    if (value == null) {
      return null;
    }
    const n = Number(value);
    if (!Number.isFinite(n) || n <= 0) {
      return null;
    }
    return Math.floor(n);
  }

  private parsePeriod(value: string | undefined): Period | undefined {
    if (value === 'monthly' || value === 'yearly') {
      return value;
    }
    return undefined;
  }

  private parseEventType(value: string | undefined): EntitlementEventType {
    const v = (value || '').trim().toUpperCase();
    switch (v) {
      case 'PURCHASED':
      case 'RENEWED':
      case 'RECOVERED':
      case 'CANCELED':
      case 'EXPIRED':
      case 'REVOKED':
      case 'REFUNDED':
      case 'ON_HOLD':
      case 'GRACE_PERIOD':
        return v;
      default:
        return 'RENEWED';
    }
  }

  private toUsage(usageBytes: number, limitBytes: number | null) {
    const percent = limitBytes && limitBytes > 0 ? Math.min(100, Math.round((usageBytes / limitBytes) * 100)) : 0;

    let state: 'ok' | 'warn' | 'critical' | 'blocked' = 'ok';
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
      used_bytes: usageBytes,
      limit_bytes: limitBytes,
      used_gb: (usageBytes / 1024 ** 3).toFixed(2),
      limit_gb: limitBytes != null ? (limitBytes / 1024 ** 3).toFixed(0) : null,
      percent,
      state,
    };
  }

  private normalizeWebhook(body: EntitlementWebhookBody): NormalizedEntitlementEvent | null {
    const userEmail = (body.userEmail || body.email || '').trim().toLowerCase();
    if (!userEmail) {
      this.logger.warn('Entitlement webhook: missing userEmail/email');
      return null;
    }

    const product = PRODUCT_MAP[body.productId];
    const storageLimitGb = Number.isFinite(body.storageLimitGb) ? Math.max(0, Math.floor(body.storageLimitGb!)) : product?.storageLimitGb ?? 0;
    const eventType = this.parseEventType(body.eventType);
    const eventTimeMs = this.parseMs(body.eventTimeMs) ?? Date.now();
    const expiresAtMs = this.parseMs(body.expiresAtMs);
    const now = Date.now();
    const hasFutureExpiry = expiresAtMs != null && expiresAtMs > now;
    const cancelAtPeriodEnd = body.cancelAtPeriodEnd ?? (eventType === 'CANCELED' && hasFutureExpiry);

    return {
      providerEventId:
        (body.providerEventId || '').trim() ||
        `legacy:${userEmail}:${body.productId}:${eventType}:${eventTimeMs}:${body.purchaseToken || 'na'}`,
      eventType,
      eventTimeMs,
      userEmail,
      platform: (body.platform || 'unknown').toLowerCase(),
      productId: body.productId,
      planCode: body.planCode || product?.planCode || body.productId,
      storageLimitGb,
      mlTier: body.mlTier ?? product?.mlTier,
      seats: body.seats ?? product?.seats,
      shareEnabled: body.shareEnabled ?? product?.shareEnabled,
      period: this.parsePeriod(body.period) ?? product?.period,
      expiresAtMs,
      purchaseToken: body.purchaseToken ?? null,
      cancelAtPeriodEnd,
      rawPayload: body as unknown as Record<string, unknown>,
    };
  }

  private mapStateToEntitlement(state: BillingSubscriptionStateRecord): EntitlementData {
    return {
      userId: state.userId,
      userEmail: state.userEmail,
      productId: state.productId,
      planCode: state.planCode,
      storageLimitGb: state.storageLimitGb,
      mlTier: (state.mlTier as MlTier | null) ?? undefined,
      seats: state.seats ?? undefined,
      shareEnabled: state.shareEnabled ?? undefined,
      period: this.parsePeriod(state.period ?? undefined),
      status: state.status,
      cancelAtPeriodEnd: state.cancelAtPeriodEnd,
      expiresAtMs: state.expiresAtMs ?? undefined,
      purchaseToken: state.purchaseToken ?? undefined,
    };
  }

  private mapStateToSubscriptionStatus(state: BillingSubscriptionStateRecord): SubscriptionStatusData {
    const freeTierQuotaGb = Math.floor(DEFAULT_FREE_TIER_QUOTA_BYTES / 1024 ** 3);
    const effectiveQuotaGb = Math.floor(Number(state.effectiveQuotaBytes ?? DEFAULT_FREE_TIER_QUOTA_BYTES) / 1024 ** 3);
    const expiresAtMs = state.expiresAtMs ?? undefined;

    return {
      status: state.status,
      productId: state.productId,
      planCode: state.planCode,
      storageLimitGb: state.storageLimitGb,
      period: this.parsePeriod(state.period ?? undefined),
      expiresAtMs,
      cancelAtPeriodEnd: state.cancelAtPeriodEnd,
      effectiveQuotaGb,
      freeTierQuotaGb,
      willDowngradeAtMs: state.cancelAtPeriodEnd ? expiresAtMs : undefined,
      serverNowMs: Date.now(),
    };
  }

  private buildNextState(params: {
    userId: string;
    current: BillingSubscriptionStateRecord | undefined;
    event: NormalizedEntitlementEvent;
  }): Insertable<BillingSubscriptionStateTable> {
    const { userId, current, event } = params;
    const now = Date.now();
    const expiresAtMs = event.expiresAtMs ?? current?.expiresAtMs ?? null;
    const hasFutureExpiry = expiresAtMs != null && expiresAtMs > now;
    const paidQuotaBytes = this.computeQuotaBytes(event.storageLimitGb);
    const freeQuotaBytes = DEFAULT_FREE_TIER_QUOTA_BYTES;

    let status = current?.status ?? 'active';
    let cancelAtPeriodEnd = event.cancelAtPeriodEnd;
    let effectiveQuotaBytes: number | null = current?.effectiveQuotaBytes ?? freeQuotaBytes;

    switch (event.eventType) {
      case 'PURCHASED':
      case 'RENEWED':
      case 'RECOVERED': {
        status = 'active';
        cancelAtPeriodEnd = false;
        effectiveQuotaBytes = paidQuotaBytes;
        break;
      }
      case 'CANCELED': {
        if (hasFutureExpiry) {
          status = 'canceled';
          cancelAtPeriodEnd = true;
          effectiveQuotaBytes = paidQuotaBytes;
        } else {
          status = 'expired';
          cancelAtPeriodEnd = false;
          effectiveQuotaBytes = freeQuotaBytes;
        }
        break;
      }
      case 'EXPIRED': {
        status = 'expired';
        cancelAtPeriodEnd = false;
        effectiveQuotaBytes = freeQuotaBytes;
        break;
      }
      case 'REVOKED':
      case 'REFUNDED': {
        status = 'revoked';
        cancelAtPeriodEnd = false;
        effectiveQuotaBytes = freeQuotaBytes;
        break;
      }
      case 'GRACE_PERIOD': {
        status = 'grace_period';
        effectiveQuotaBytes = hasFutureExpiry ? paidQuotaBytes : freeQuotaBytes;
        break;
      }
      case 'ON_HOLD': {
        status = 'on_hold';
        effectiveQuotaBytes = hasFutureExpiry ? paidQuotaBytes : freeQuotaBytes;
        break;
      }
    }

    return {
      userId,
      userEmail: event.userEmail,
      platform: event.platform,
      productId: event.productId,
      planCode: event.planCode,
      storageLimitGb: event.storageLimitGb,
      mlTier: event.mlTier ?? current?.mlTier ?? null,
      seats: event.seats ?? current?.seats ?? null,
      shareEnabled: event.shareEnabled ?? current?.shareEnabled ?? null,
      period: event.period ?? this.parsePeriod(current?.period ?? undefined) ?? null,
      purchaseToken: event.purchaseToken ?? current?.purchaseToken ?? null,
      expiresAtMs,
      status,
      cancelAtPeriodEnd,
      lastEventTimeMs: event.eventTimeMs,
      lastEventId: event.providerEventId,
      effectiveQuotaBytes,
    };
  }

  private async scheduleExpiryJobIfNeeded(state: Insertable<BillingSubscriptionStateTable>): Promise<void> {
    if (!state.cancelAtPeriodEnd || !state.expiresAtMs) {
      return;
    }

    const now = Date.now();
    if (state.expiresAtMs <= now) {
      return;
    }

    const delayMs = state.expiresAtMs - now + 1000;
    await this.jobRepository.queue({
      name: JobName.BillingApplyExpiry,
      data: { userId: state.userId, expectedExpiresAtMs: state.expiresAtMs, delayMs },
    });
  }

  private async applyExpiryForUser(userId: string, expectedExpiresAtMs?: number): Promise<void> {
    const state = await this.subscriptionRepository.getStateByUserId(userId);
    if (!state || !state.cancelAtPeriodEnd || !state.expiresAtMs) {
      return;
    }

    const expiresAtMs = Number(state.expiresAtMs);
    const now = Date.now();
    if (expiresAtMs > now) {
      return;
    }

    if (expectedExpiresAtMs != null && Number(expectedExpiresAtMs) !== expiresAtMs) {
      return;
    }

    const freeQuotaBytes = DEFAULT_FREE_TIER_QUOTA_BYTES;
    await this.subscriptionRepository.updateState(userId, {
      status: 'expired',
      cancelAtPeriodEnd: false,
      effectiveQuotaBytes: freeQuotaBytes,
      lastEventTimeMs: Math.max(Number(state.lastEventTimeMs), now),
      lastEventId: `system-expiry:${expiresAtMs}`,
    });

    await this.userAdmin.updateUserQuota(userId, freeQuotaBytes);
  }

  @OnJob({ name: JobName.BillingApplyExpiry, queue: QueueName.BackgroundTask })
  async handleApplyExpiryJob(data: { userId: string; expectedExpiresAtMs?: number }) {
    await this.applyExpiryForUser(data.userId, this.parseMs(data.expectedExpiresAtMs) ?? undefined);
  }

  @OnEvent({ name: 'AppBootstrap', workers: [ImmichWorker.Api] })
  async reconcileExpiredSubscriptions() {
    const nowMs = Date.now();
    const due = await this.subscriptionRepository.findStatesDueForExpiry(nowMs, 200);
    for (const state of due) {
      await this.applyExpiryForUser(state.userId, Number(state.expiresAtMs));
    }
  }

  async getUsage(auth: AuthDto) {
    const me = await this.userAdmin.get(auth, auth.user.id);
    return this.toUsage(me.quotaUsageInBytes ?? 0, me.quotaSizeInBytes ?? null);
  }

  async getUsageByUserEmail(email: string) {
    const user = await this.userAdmin.getByEmail(email);
    return this.toUsage(user?.quotaUsageInBytes ?? 0, user?.quotaSizeInBytes ?? null);
  }

  async getEntitlement(userId: string): Promise<EntitlementData | null> {
    const state = await this.subscriptionRepository.getStateByUserId(userId);
    return state ? this.mapStateToEntitlement(state) : null;
  }

  async getSubscriptionStatus(userId: string): Promise<SubscriptionStatusData | null> {
    const state = await this.subscriptionRepository.getStateByUserId(userId);
    return state ? this.mapStateToSubscriptionStatus(state) : null;
  }

  async handleEntitlementWebhook(body: EntitlementWebhookBody): Promise<{ ok: true }> {
    const event = this.normalizeWebhook(body);
    if (!event) {
      return { ok: true };
    }

    const user = await this.userAdmin.getByEmail(event.userEmail);
    if (!user) {
      this.logger.warn(`Entitlement webhook: user not found for email=${event.userEmail}`);
      return { ok: true };
    }

    const inserted = await this.subscriptionRepository.insertEventIfNotExists({
      userId: user.id,
      providerEventId: event.providerEventId,
      platform: event.platform,
      eventType: event.eventType,
      eventTimeMs: event.eventTimeMs,
      payload: event.rawPayload,
      processResult: null,
    });
    if (!inserted) {
      return { ok: true };
    }

    const current = await this.subscriptionRepository.getStateByUserId(user.id);
    if (current && Number(current.lastEventTimeMs) > event.eventTimeMs) {
      await this.subscriptionRepository.updateEventProcessResult(event.providerEventId, 'ignored_out_of_order');
      return { ok: true };
    }

    const nextState = this.buildNextState({
      userId: user.id,
      current,
      event,
    });

    await this.subscriptionRepository.upsertState(nextState);
    await this.userAdmin.updateUserQuota(user.id, nextState.effectiveQuotaBytes ?? null);
    await this.subscriptionRepository.updateEventProcessResult(event.providerEventId, 'applied');
    await this.scheduleExpiryJobIfNeeded(nextState);

    return { ok: true };
  }
}
