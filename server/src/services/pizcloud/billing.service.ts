// server/src/services/billing.service.ts
import { Injectable, Logger } from '@nestjs/common';
import axios from 'axios';
import { AuthDto } from 'src/dtos/auth.dto';
import { getGoogleAccessToken } from 'src/services/pizcloud/google-auth';
import { UserAdminService } from 'src/services/user-admin.service';

export type Period = 'monthly' | 'yearly';

export type EntitlementWebhookBody = {
  userId: string;
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

// type for RTDN Pub/Sub push
type AndroidRtdnPushBody = {
  message?: {
    messageId?: string;
    publishTime?: string;
    data?: string; // base64 encoded JSON
    attributes?: Record<string, string>;
  };
  subscription?: string;
};

// payload decode from data in RTDN (Android)
type AndroidRtdnDecoded = {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: {
    version?: string;
    notificationType?: number;
    purchaseToken?: string;
    subscriptionId?: string;
  };
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

  // =========================================================
  //  VERIFY ANDROID
  // =========================================================
  async verifyAndroidPurchase(params: {
    userId: string | undefined;
    userEmail: string | undefined;
    productId: string;
    purchaseToken: string;
    packageName: string;
  }): Promise<{ ok: true }> {
    const { userId, userEmail, productId, purchaseToken, packageName } = params;

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
      userEmail: userEmail,
      productId,
      planCode: ent.planCode,
      storageLimitGb: ent.storageLimitGb,
      mlTier: ent.mlTier,
      seats: ent.seats,
      shareEnabled: ent.shareEnabled,
      period: ent.period,
      expiresAtMs: exp,
      purchaseToken,
    };

    const quotaSizeInBytes = this.computeQuotaBytes(payload.storageLimitGb);

    await this.userAdmin.updateUserQuota(payload.userId, quotaSizeInBytes);
    this.entitlements.set(payload.userId, payload);

    this.purchaseTokenToUser.set(purchaseToken, {
      userId: payload.userId,
      userEmail: payload.userEmail,
      productId,
    });

    return { ok: true };
  }

  async verifyIOSPurchase(params: {
    userId: string | undefined;
    userEmail: string | undefined;
    productId: string;
    receiptData: string;
  }): Promise<{ ok: true }> {
    const { userId, userEmail, productId, receiptData } = params;

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
      userEmail,
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


  // =========================================================
  //  RTDN HANDLER – Android
  //  POST /api/billing/iap/android/rtdn
  // =========================================================
  async handleAndroidRtdn(body: AndroidRtdnPushBody): Promise<void> {
    const message = body?.message;
    const dataBase64 = message?.data;
    if (!dataBase64) {
      this.logger.warn('RTDN: missing message.data');
      return;
    }

    const decodedJson = Buffer.from(dataBase64, 'base64').toString('utf8');
    let decoded: AndroidRtdnDecoded;
    try {
      decoded = JSON.parse(decodedJson);
    } catch (e) {
      this.logger.error('RTDN: failed to parse data JSON', e as any);
      return;
    }

    const subNoti = decoded.subscriptionNotification;
    if (!subNoti) {
      this.logger.warn('RTDN: no subscriptionNotification in message');
      return;
    }

    const packageName = decoded.packageName;
    const productId = subNoti.subscriptionId;
    const purchaseToken = subNoti.purchaseToken;
    const notificationType = subNoti.notificationType;

    this.logger.log(
      `RTDN: pkg=${packageName} productId=${productId} token=${purchaseToken} type=${notificationType}`,
    );

    if (!packageName || !productId || !purchaseToken) {
      this.logger.warn('RTDN: missing required fields');
      return;
    }

    const subInfo = await this.fetchAndroidSubscriptionInfo(
      packageName,
      productId,
      purchaseToken,
    );

    const expiryTimeMillis = Number(subInfo.expiryTimeMillis ?? 0);
    const priceAmountMicros = Number(subInfo.priceAmountMicros ?? 0);
    const priceCurrencyCode = subInfo.priceCurrencyCode as string | undefined;

    const amount = priceAmountMicros ? priceAmountMicros / 1e6 : undefined;

    const mapping = this.purchaseTokenToUser.get(purchaseToken);
    if (!mapping) {
      // fallback: scan entitlements map
      for (const ent of this.entitlements.values()) {
        if (ent.purchaseToken === purchaseToken) {
          this.purchaseTokenToUser.set(purchaseToken, {
            userId: ent.userId,
            userEmail: ent.userEmail,
            productId: ent.productId,
          });
          break;
        }
      }
    }

    const finalMapping = this.purchaseTokenToUser.get(purchaseToken);
    if (!finalMapping) {
      this.logger.error(
        `RTDN: cannot find user mapping for purchaseToken=${purchaseToken}`,
      );
      return;
    }

    const { userId, userEmail } = finalMapping;

    const ent = PRODUCT_MAP[productId];
    if (!ent) {
      this.logger.error(`RTDN: Unknown productId="${productId}"`);
    } else {
      const payload: EntitlementData = {
        userId,
        userEmail,
        productId,
        planCode: ent.planCode,
        storageLimitGb: ent.storageLimitGb,
        mlTier: ent.mlTier,
        seats: ent.seats,
        shareEnabled: ent.shareEnabled,
        period: ent.period,
        expiresAtMs: expiryTimeMillis || undefined,
        purchaseToken,
      };

      const quotaSizeInBytes = this.computeQuotaBytes(payload.storageLimitGb);
      await this.userAdmin.updateUserQuota(payload.userId, quotaSizeInBytes);
      this.entitlements.set(payload.userId, payload);
    }

    await this.notifyPizCloudVerifiedPurchase({
      email: userEmail,
      productId,
      platform: 'android',
      amount,
      currency: priceCurrencyCode,
      isRenewal: true,
      billingPeriod: ent?.period ?? 'monthly',
      periodEnd: expiryTimeMillis
        ? new Date(expiryTimeMillis).toISOString()
        : undefined,
      purchaseToken,
    });
  }

  private async fetchAndroidSubscriptionInfo(
    packageName: string,
    productId: string,
    purchaseToken: string,
  ): Promise<any> {
    const accessToken = await getGoogleAccessToken();
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;

    const { data } = await axios.get(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
      timeout: 8000,
    });

    return data;
  }

  private async notifyPizCloudVerifiedPurchase(params: {
    email?: string;
    productId: string;
    platform: 'android' | 'ios';
    amount?: number;
    currency?: string;
    isRenewal?: boolean;
    billingPeriod?: string;
    periodStart?: string;
    periodEnd?: string;
    purchaseToken?: string;
  }) {
    const base =
      process.env.PIZCLOUD_BASE_URL || 'http://127.0.0.1:3000';
    const url = `${base}/internal/billing/verify-success`;
    const internalKey = process.env.PIZCLOUD_INTERNAL_KEY;

    if (!internalKey) {
      this.logger.error(
        'notifyPizCloudVerifiedPurchase: missing PIZCLOUD_INTERNAL_KEY',
      );
      return;
    }

    try {
      await axios.post(
        url,
        {
          email: params.email,
          productId: params.productId,
          platform: params.platform,
          amount: params.amount,
          currency: params.currency,
          isRenewal: params.isRenewal,
          billingPeriod: params.billingPeriod,
          periodStart: params.periodStart,
          periodEnd: params.periodEnd,
          purchaseToken: params.purchaseToken,
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'x-internal-key': internalKey,
          },
          timeout: 8000,
        },
      );
      this.logger.log(
        `notifyPizCloudVerifiedPurchase: sent to pizCloud for productId=${params.productId}`,
      );
    } catch (e: any) {
      this.logger.error(
        'notifyPizCloudVerifiedPurchase: failed to call pizCloud',
        e?.message || e,
      );
    }
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
