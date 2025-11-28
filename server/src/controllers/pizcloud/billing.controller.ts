// server/src/controllers/pizcloud/billing.controller.ts
import { Body, Controller, Get, HttpCode, HttpStatus, Post, Req, UnauthorizedException } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto';
import { Auth, Authenticated } from 'src/middleware/auth.guard';
import { BillingService } from 'src/services/pizcloud/billing.service';

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
