// server/src/services/billing.service.ts
import { Injectable } from '@nestjs/common';
import axios from 'axios';
import { AuthDto } from 'src/dtos/auth.dto';
import { getGoogleAccessToken } from 'src/services/pizcloud/google-auth';
import { UserAdminService } from 'src/services/user-admin.service';

export type Period = 'monthly' | 'yearly';

export type EntitlementWebhookBody = {
  userId: string;
  productId: string;
  planCode: string;        // '100G' | '200G' | '2TB' | ...
  storageLimitGb: number;  // 100, 200, 2000, ...
  mlTier?: 'free' | 'pro' | 'priority';
  seats?: number;
  shareEnabled?: boolean;
  signature: string;       // HMAC-SHA256(JSON(payload_without_signature))
};

type MlTier = 'free' | 'pro' | 'priority';

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
  productId: string;
  planCode: string;
  storageLimitGb: number;
  mlTier?: MlTier;
  seats?: number;
  shareEnabled?: boolean;
  period?: Period;
  expiresAtMs?: number;
};

const PRODUCT_MAP: Record<string, ProductInfo> = {
  // 100 GB
  'storage_100g_monthly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_100g_yearly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'yearly' },

  // 200 GB
  'storage_200g_monthly': { planCode: '200G', storageLimitGb: 200, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'monthly' },
  'storage_200g_yearly': { planCode: '200G', storageLimitGb: 200, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'yearly' },

  // 2 TB
  'storage_2tb_monthly': { planCode: '2TB', storageLimitGb: 2000, mlTier: 'priority', seats: 5, shareEnabled: true, period: 'monthly' },
  'storage_2tb_yearly': { planCode: '2TB', storageLimitGb: 2000, mlTier: 'priority', seats: 5, shareEnabled: true, period: 'yearly' },
};

@Injectable()
export class BillingService {
  private readonly entitlements = new Map<string, EntitlementData>();

  constructor(
    private readonly userAdmin: UserAdminService,
  ) { }

  private computeQuotaBytes(storageLimitGb: number): number | null {
    const limitGiB = Number.isFinite(storageLimitGb)
      ? Math.max(0, Math.floor(storageLimitGb))
      : 0;

    if (limitGiB === 0) return 0;
    return limitGiB * 1024 ** 3;
  }

  async verifyAndroidPurchase(params: {
    userId: string | undefined;
    productId: string;
    purchaseToken: string;
    packageName: string;
  }): Promise<{ ok: true }> {
    const { userId, productId, purchaseToken, packageName } = params;

    const accessToken = await getGoogleAccessToken();
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;

    const { data } = await axios.get(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
      timeout: 8000,
    });

    const now = Date.now();
    const exp = Number(data.expiryTimeMillis ?? 0);
    if (!exp || exp <= now) {
      throw new Error('Android subscription expired or invalid');
    }

    const ent = PRODUCT_MAP[productId];
    if (!ent) throw new Error('Unknown productId');

    const payload: EntitlementData = {
      userId: userId as string,
      productId,
      planCode: ent.planCode,
      storageLimitGb: ent.storageLimitGb,
      mlTier: ent.mlTier,
      seats: ent.seats,
      shareEnabled: ent.shareEnabled,
      period: ent.period,
      expiresAtMs: exp,
    };

    const quotaSizeInBytes = this.computeQuotaBytes(payload.storageLimitGb);

    await this.userAdmin.updateUserQuota(payload.userId, quotaSizeInBytes);
    this.entitlements.set(payload.userId, payload);

    return { ok: true };
  }

  async verifyIOSPurchase(params: {
    userId: string | undefined;
    productId: string;
    receiptData: string;
  }): Promise<{ ok: true }> {
    const { userId, productId, receiptData } = params;

    const endpoint = process.env.IOS_RECEIPT_ENDPOINT ?? 'https://buy.itunes.apple.com/verifyReceipt';
    const secret = process.env.APPLE_IAP_SHARED_SECRET;
    if (!secret) {
      throw new Error('APPLE_IAP_SHARED_SECRET is required for iOS verification');
    }
    const verify = async (url: string) =>
      (
        await axios.post(
          url,
          { 'receipt-data': receiptData, password: secret, 'exclude-old-transactions': true },
          { timeout: 8000 }
        )
      ).data;

    let data = await verify(endpoint);
    // 21007 → sandbox
    if (data?.status === 21007) {
      data = await verify('https://sandbox.itunes.apple.com/verifyReceipt');
    }
    if (data?.status !== 0) {
      throw new Error(`iOS verify failed: ${data?.status}`);
    }

    const now = Date.now();
    const items: any[] = (data.latest_receipt_info || data.receipt?.in_app || []);

    const ent = PRODUCT_MAP[productId];
    if (!ent) throw new Error('Unknown productId');

    const match = items
      .filter((i) => i.product_id === productId)
      .map((i) => Number(i.expires_date_ms ?? 0))
      .sort((a, b) => b - a)[0];

    if (!match || match <= now) {
      throw new Error('iOS subscription not active');
    }

    const payload: EntitlementData = {
      userId: userId as string,
      productId,
      planCode: ent.planCode,
      storageLimitGb: ent.storageLimitGb,
      mlTier: ent.mlTier,
      seats: ent.seats,
      shareEnabled: ent.shareEnabled,
      period: ent.period,
      expiresAtMs: match,
    };

    const quotaSizeInBytes = this.computeQuotaBytes(payload.storageLimitGb);

    await this.userAdmin.updateUserQuota(payload.userId, quotaSizeInBytes);
    this.entitlements.set(payload.userId, payload);

    return { ok: true };
  }

  async getUsage(auth: AuthDto) {
    const me = await this.userAdmin.get(auth, auth.user.id);
    const stats = await this.userAdmin.getStatistics(auth, auth.user.id, {} as any);

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

  getEntitlement(userId: string): EntitlementData | null {
    return this.entitlements.get(userId) ?? null;
  }

  // async handleEntitlementWebhook(
  //   body: EntitlementWebhookBody,
  //   authorizationHeader: string | undefined,
  // ): Promise<{ ok: true }> {
  //   // Check service token
  //   const token = (authorizationHeader || '').replace(/^Bearer\s+/i, '');
  //   if (token !== process.env.BILLING_SERVICE_TOKEN) {
  //     throw new UnauthorizedException('Invalid service token');
  //   }

  //   const { signature, ...payloadWithoutSignature } = body;
  //   const secret = process.env.ENTITLEMENT_HMAC_SECRET;
  //   if (!secret) {
  //     throw new UnauthorizedException('HMAC secret not configured');
  //   }

  //   const expected = crypto
  //     .createHmac('sha256', secret)
  //     .update(JSON.stringify(payloadWithoutSignature))
  //     .digest('hex');

  //   if (signature !== expected) {
  //     throw new UnauthorizedException('Bad HMAC signature');
  //   }

  //   const quotaSizeInBytes = this.computeQuotaBytes(body.storageLimitGb);
  //   await this.userAdmin.updateUserQuota(body.userId, quotaSizeInBytes);

  //   const entitlement: EntitlementData = {
  //     ...payloadWithoutSignature,
  //   };

  //   this.entitlements.set(body.userId, entitlement);

  //   return { ok: true };
  // }
}
