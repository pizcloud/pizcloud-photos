// server/src/services/billing.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto';
import { UserAdminService } from 'src/services/user-admin.service';

export type Period = 'monthly' | 'yearly';

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
};

const PRODUCT_MAP: Record<string, ProductInfo> = {
  // 50 GB
  'storage_50gb_monthly': { planCode: '50GB', storageLimitGb: 50, mlTier: 'basic', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_50gb_yearly': { planCode: '50GB', storageLimitGb: 50, mlTier: 'basic', seats: 1, shareEnabled: true, period: 'yearly' },

  // 100 GB
  'storage_100g_monthly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro1', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_100g_yearly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro1', seats: 1, shareEnabled: true, period: 'yearly' },

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

  private readonly entitlements = new Map<string, EntitlementData>();

  private readonly purchaseTokenToUser = new Map<
    string,
    { userId: string; userEmail?: string; productId: string }
  >();

  constructor(private readonly userAdmin: UserAdminService,) { }

  private computeQuotaBytes(storageLimitGb: number): number | null {
    const limitGiB = Number.isFinite(storageLimitGb)
      ? Math.max(0, Math.floor(storageLimitGb))
      : 0;

    if (limitGiB === 0) return 0;
    return limitGiB * 1024 ** 3;
  }

  async getUsage(auth: AuthDto) {
    const me = await this.userAdmin.get(auth, auth.user.id);
    // const stats = await this.userAdmin.getStatistics(auth, auth.user.id, {} as any);

    const usage = me.quotaUsageInBytes ?? 0;
    const limit = me.quotaSizeInBytes; // null = unlimited

    const percent = limit && limit > 0 ? Math.min(100, Math.round((usage / limit) * 100)) : 0;

    let state: 'ok' | 'warn' | 'critical' | 'blocked' = 'ok';
    if (limit && limit > 0) {
      if (percent >= 100) state = 'blocked';
      else if (percent >= 90) state = 'critical';
      else if (percent >= 80) state = 'warn';
    }

    return {
      used_bytes: usage,
      limit_bytes: limit, // number | null
      used_gb: (usage / (1024 ** 3)).toFixed(2),
      limit_gb: limit != null ? (limit / (1024 ** 3)).toFixed(0) : null,
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
      if (percent >= 100) state = 'blocked';
      else if (percent >= 90) state = 'critical';
      else if (percent >= 80) state = 'warn';
    }

    return {
      used_bytes: usage,
      limit_bytes: limit, // number | null
      used_gb: (usage / (1024 ** 3)).toFixed(2),
      limit_gb: limit != null ? (limit / (1024 ** 3)).toFixed(0) : null,
      percent,
      state,
    };
  }

  getEntitlement(userId: string): EntitlementData | null {
    return this.entitlements.get(userId) ?? null;
  }

  async handleEntitlementWebhook(body: EntitlementWebhookBody,): Promise<{ ok: true }> {

    const { ...payloadWithoutSignature } = body;

    const quotaSizeInBytes = this.computeQuotaBytes(body.storageLimitGb);
    // NOTE: previous logic used body.userId directly.
    // await this.userAdmin.updateUserQuota(body.userId, quotaSizeInBytes);

    // NOTE: new logic resolves the Immich user by email.
    const user = await this.userAdmin.getByEmail(body.email);
    if (!user) {
      this.logger.warn(`Entitlement webhook: user not found for email=${body.email}`);
      return { ok: true };
    }

    const resolvedUserId = user.id;
    await this.userAdmin.updateUserQuota(resolvedUserId, quotaSizeInBytes);

    const entitlement: EntitlementData = {
      ...payloadWithoutSignature,
      // NOTE: ensure we store the Immich user id, not the external one.
      userId: resolvedUserId,
      userEmail: body.email,
    };

    // NOTE: previous logic stored by body.userId.
    // this.entitlements.set(body.userId, entitlement);
    this.entitlements.set(resolvedUserId, entitlement);

    return { ok: true };
  }
}
