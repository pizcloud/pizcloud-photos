
// // server/src/controllers/billing.controller.ts
// import { Body, Controller, Get, Headers, HttpCode, HttpStatus, Post, Req, UnauthorizedException } from '@nestjs/common';
// import axios from 'axios';
// import crypto from 'node:crypto';
// import { AuthDto } from 'src/dtos/auth.dto';
// import { Auth, Authenticated } from 'src/middleware/auth.guard';
// import { UserRepository } from 'src/repositories/user.repository';
// import { getGoogleAccessToken } from 'src/services/google-auth';
// import { UserAdminService } from 'src/services/user-admin.service';

// type Period = 'monthly' | 'yearly';

// type EntitlementWebhookBody = {
//   userId: string;
//   productId: string;
//   planCode: string;        // '100G' | '200G' | '2TB' | ...
//   storageLimitGb: number;  // 100, 200, 2000, ...
//   mlTier?: 'free' | 'pro' | 'priority';
//   seats?: number;
//   shareEnabled?: boolean;
//   signature: string;       // HMAC-SHA256(JSON(payload_without_signature))
// };

// const PRODUCT_MAP: Record<
//   string,
//   {
//     planCode: string;
//     storageLimitGb: number;
//     mlTier: 'free' | 'pro' | 'priority';
//     seats: number;
//     shareEnabled: boolean;
//     period: Period;
//   }
// > = {
//   // 100 GB
//   'storage_100g_monthly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'monthly' },
//   'storage_100g_yearly': { planCode: '100G', storageLimitGb: 100, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'yearly' },

//   // 200 GB
//   'storage_200g_monthly': { planCode: '200G', storageLimitGb: 200, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'monthly' },
//   'storage_200g_yearly': { planCode: '200G', storageLimitGb: 200, mlTier: 'pro', seats: 1, shareEnabled: true, period: 'yearly' },

//   // 2 TB
//   'storage_2tb_monthly': { planCode: '2TB', storageLimitGb: 2000, mlTier: 'priority', seats: 5, shareEnabled: true, period: 'monthly' },
//   'storage_2tb_yearly': { planCode: '2TB', storageLimitGb: 2000, mlTier: 'priority', seats: 5, shareEnabled: true, period: 'yearly' },
// };

// const ENTITLEMENTS = new Map<string, Omit<EntitlementWebhookBody, 'signature'>>();

// //   - POST /api/billing/entitlements/webhook
// //   - GET  /api/billing/usage
// @Controller('billing')
// export class BillingController {
//   constructor(
//     private readonly userAdmin: UserAdminService,
//     private readonly userRepository: UserRepository,
//   ) { }

//   @Post('/iap/android/verify')
//   @HttpCode(HttpStatus.OK)
//   async verifyAndroid(@Req() req: any, @Body() b: { productId: string; purchaseToken: string; packageName: string }) {
//     const userId = req.user?.id;
//     const productId = b.productId;
//     const purchaseToken = b.purchaseToken;
//     const packageName = b.packageName;

//     const accessToken = await getGoogleAccessToken();
//     const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;

//     const { data } = await axios.get(url, {
//       headers: { Authorization: `Bearer ${accessToken}` },
//       timeout: 8000,
//     });

//     const now = Date.now();
//     const exp = Number(data.expiryTimeMillis ?? 0);
//     if (!exp || exp <= now) {
//       throw new Error('Android subscription expired or invalid');
//     }

//     const ent = PRODUCT_MAP[productId];
//     if (!ent) throw new Error('Unknown productId');
//     const payload = {
//       userId,
//       productId,
//       planCode: ent.planCode,
//       storageLimitGb: ent.storageLimitGb,
//       mlTier: ent.mlTier,
//       seats: ent.seats,
//       shareEnabled: ent.shareEnabled,
//       period: ent.period,
//       expiresAtMs: exp
//     };
//     const limitGiB = Number.isFinite(payload.storageLimitGb) ? Math.max(0, Math.floor(payload.storageLimitGb)) : 0;
//     const quotaSizeInBytes: number | null = limitGiB === 0 ? 0 : limitGiB * 1024 ** 3;


//     await this.userAdmin.updateUserQuota(payload.userId, quotaSizeInBytes);

//     ENTITLEMENTS.set(payload.userId, payload);

//     return { ok: true };
//   }

//   @Post('entitlements/webhook')
//   async webhook(@Body() body: EntitlementWebhookBody, @Headers('authorization') auth: string) {
//     const token = (auth || '').replace(/^Bearer\s+/i, '');
//     if (token !== process.env.BILLING_SERVICE_TOKEN) {
//       throw new UnauthorizedException('Invalid service token');
//     }

//     const { signature, ...payload } = body;
//     const secret = process.env.ENTITLEMENT_HMAC_SECRET;
//     if (!secret) throw new UnauthorizedException('HMAC secret not configured');

//     const expected = crypto.createHmac('sha256', secret).update(JSON.stringify(payload)).digest('hex');
//     if (signature !== expected) {
//       throw new UnauthorizedException('Bad HMAC signature');
//     }

//     const limitGiB = Number.isFinite(payload.storageLimitGb) ? Math.max(0, Math.floor(payload.storageLimitGb)) : 0;
//     const quotaSizeInBytes: number | null = limitGiB === 0 ? 0 : limitGiB * 1024 ** 3;
//     await this.userAdmin.updateUserQuota(body.userId, quotaSizeInBytes);

//     ENTITLEMENTS.set(body.userId, payload);

//     return { ok: true };
//   }

//   @Get('usage')
//   @Authenticated()
//   async usage(@Auth() auth: AuthDto) {
//     const me = await this.userAdmin.get(auth, auth.user.id);

//     const stats = await this.userAdmin.getStatistics(auth, auth.user.id, {} as any);
//     const usage = Number((stats as any).usage ?? 0);
//     const limit = me.quotaSizeInBytes; // null = unlimited

//     const percent = limit && limit > 0 ? Math.min(100, Math.round((usage / limit) * 100)) : 0;
//     let state: 'ok' | 'warn' | 'critical' | 'blocked' = 'ok';
//     if (limit && limit > 0) {
//       if (percent >= 100) state = 'blocked';
//       else if (percent >= 90) state = 'critical';
//       else if (percent >= 80) state = 'warn';
//     }

//     return {
//       used_bytes: usage,
//       limit_bytes: limit,                                  // number | null
//       used_gb: (usage / (1024 ** 3)).toFixed(2),
//       limit_gb: limit != null ? (limit / (1024 ** 3)).toFixed(0) : null,
//       percent,
//       state,
//     };
//   }

//   @Get('entitlements')
//   async getEntitlement(@Req() req: Request) {
//     const userId = (req as any)?.user?.id;
//     if (!userId) {
//       throw new UnauthorizedException('No authenticated user');
//     }
//     const ent = ENTITLEMENTS.get(userId);
//     return ent ?? null;
//   }
// }

// server/src/controllers/billing.controller.ts
import { Body, Controller, Get, HttpCode, HttpStatus, Post, Req, UnauthorizedException } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto';
import { Auth, Authenticated } from 'src/middleware/auth.guard';
import { BillingService } from 'src/services/billing.service';

@Controller('billing')
export class BillingController {
  constructor(
    private readonly billingService: BillingService,
  ) { }

  // POST /api/billing/iap/android/verify
  @Post('iap/android/verify')
  @HttpCode(HttpStatus.OK)
  async verifyAndroid(
    @Req() req: any,
    @Body() b: { productId: string; purchaseToken: string; packageName: string },
  ) {
    const userId = req.user?.id as string | undefined;

    return this.billingService.verifyAndroidPurchase({
      userId,
      productId: b.productId,
      purchaseToken: b.purchaseToken,
      packageName: b.packageName,
    });
  }

  // POST /api/billing/iap/ios/verify
  @Post('iap/ios/verify')
  @HttpCode(HttpStatus.OK)
  async verifyIOS(
    @Req() req: any,
    @Body() b: { productId: string; receiptData: string },
  ) {
    const userId = req.user?.id as string | undefined;

    return this.billingService.verifyIOSPurchase({
      userId,
      productId: b.productId,
      receiptData: b.receiptData
    });
  }

  // GET /api/billing/usage
  @Get('usage')
  @Authenticated()
  async usage(@Auth() auth: AuthDto) {
    return this.billingService.getUsage(auth);
  }

  // GET /api/billing/entitlements
  @Get('entitlements')
  async getEntitlement(@Req() req: Request) {
    const userId = (req as any)?.user?.id as string | undefined;
    if (!userId) {
      throw new UnauthorizedException('No authenticated user');
    }

    return this.billingService.getEntitlement(userId);
  }

  // // POST /api/billing/entitlements/webhook
  // @Post('entitlements/webhook')
  // async webhook(
  //   @Body() body: EntitlementWebhookBody,
  //   @Headers('authorization') auth: string,
  // ) {
  //   return this.billingService.handleEntitlementWebhook(body, auth);
  // }
}
