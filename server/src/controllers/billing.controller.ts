
// server/src/controllers/billing.controller.ts
import { Body, Controller, Get, Headers, Post, Req, UnauthorizedException } from '@nestjs/common';
import crypto from 'node:crypto';
import { AuthDto } from 'src/dtos/auth.dto';
import { Auth, Authenticated } from 'src/middleware/auth.guard';
import { UserRepository } from 'src/repositories/user.repository';
import { UserAdminService } from 'src/services/user-admin.service';

type EntitlementWebhookBody = {
  userId: string;
  productId: string;
  planCode: string;        // '100G' | '200G' | '2TB' | ...
  storageLimitGb: number;  // 100, 200, 2000, ...
  mlTier?: 'free' | 'pro' | 'priority';
  seats?: number;
  shareEnabled?: boolean;
  signature: string;       // HMAC-SHA256(JSON(payload_without_signature))
};

const ENTITLEMENTS = new Map<string, Omit<EntitlementWebhookBody, 'signature'>>();

//   - POST /api/billing/entitlements/webhook
//   - GET  /api/billing/usage
@Controller('billing')
export class BillingController {
  constructor(
    private readonly userAdmin: UserAdminService,
    private readonly userRepository: UserRepository,
  ) { }

  @Post('entitlements/webhook')
  async webhook(@Body() body: EntitlementWebhookBody, @Headers('authorization') auth: string) {
    const token = (auth || '').replace(/^Bearer\s+/i, '');
    if (token !== process.env.BILLING_SERVICE_TOKEN) {
      throw new UnauthorizedException('Invalid service token');
    }

    const { signature, ...payload } = body;
    const secret = process.env.ENTITLEMENT_HMAC_SECRET;
    if (!secret) throw new UnauthorizedException('HMAC secret not configured');

    const expected = crypto.createHmac('sha256', secret).update(JSON.stringify(payload)).digest('hex');
    if (signature !== expected) {
      throw new UnauthorizedException('Bad HMAC signature');
    }

    const limitGiB = Number.isFinite(payload.storageLimitGb) ? Math.max(0, Math.floor(payload.storageLimitGb)) : 0;
    const quotaSizeInBytes: number | null = limitGiB === 0 ? 0 : limitGiB * 1024 ** 3;
    await this.userAdmin.updateUserQuota(body.userId, quotaSizeInBytes);

    ENTITLEMENTS.set(body.userId, payload);

    return { ok: true };
  }

  @Get('usage')
  @Authenticated()
  async usage(@Auth() auth: AuthDto) {
    const me = await this.userAdmin.get(auth, auth.user.id);

    const stats = await this.userAdmin.getStatistics(auth, auth.user.id, {} as any);
    const usage = Number((stats as any).usage ?? 0);
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
      limit_bytes: limit,                                  // number | null
      used_gb: (usage / (1024 ** 3)).toFixed(2),
      limit_gb: limit != null ? (limit / (1024 ** 3)).toFixed(0) : null,
      percent,
      state,
    };
  }

  @Get('entitlements')
  async getEntitlement(@Req() req: Request) {
    const userId = (req as any)?.user?.id;
    if (!userId) {
      throw new UnauthorizedException('No authenticated user');
    }
    const ent = ENTITLEMENTS.get(userId);
    return ent ?? null;
  }
}
