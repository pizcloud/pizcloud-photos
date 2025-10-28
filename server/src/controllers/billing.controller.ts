// server/src/controllers/billing.controller.ts
import { Body, Controller, Headers, Post, UnauthorizedException } from '@nestjs/common';
import crypto from 'node:crypto';
import { UserAdminService } from 'src/services/user-admin.service';

type EntitlementWebhookBody = {
  userId: string;
  planCode: string;        // Ex: '100G' | '200G' | '2TB'
  storageLimitGb: number;  // Ex: 100, 200, 2000 (GiB)
  mlTier?: 'free' | 'pro' | 'priority';
  seats?: number;
  shareEnabled?: boolean;
  signature: string;       // HMAC-SHA256(JSON(payload_without_signature))
};

@Controller('billing/entitlements')
export class BillingController {
  constructor(private readonly userAdmin: UserAdminService) { }

  @Post('webhook')
  async webhook(@Body() body: EntitlementWebhookBody, @Headers('authorization') auth: string) {
    // 1) Service token
    const token = (auth || '').replace(/^Bearer\s+/i, '');
    if (token !== process.env.BILLING_SERVICE_TOKEN) {
      throw new UnauthorizedException('Invalid service token');
    }

    // 2) HMAC
    const { signature, ...payload } = body;
    const secret = process.env.ENTITLEMENT_HMAC_SECRET;
    if (!secret) throw new UnauthorizedException('HMAC secret not configured');
    const expected = crypto.createHmac('sha256', secret).update(JSON.stringify(payload)).digest('hex');
    if (signature !== expected) {
      throw new UnauthorizedException('Bad HMAC signature');
    }

    // 3) GiB -> bytes (API Admin get BYTES: number)
    //    Core convention for user quota:
    //     - null => unlimited
    //     - 0    => no-upload
    //     - >0   => limit (bytes)
    const limitGiB = Number.isFinite(payload.storageLimitGb) ? Math.max(0, Math.floor(payload.storageLimitGb)) : 0;

    // const quotaSizeInBytes: number | null = (payload.planCode === 'UNLIMITED') ? null
    //   : (limitGiB === 0 ? 0 : limitGiB * 1024 ** 3);

    const quotaSizeInBytes: number | null = limitGiB === 0 ? 0 : limitGiB * 1024 ** 3;

    await this.userAdmin.updateUserQuota(body.userId, quotaSizeInBytes);
    return { ok: true };
  }
}
