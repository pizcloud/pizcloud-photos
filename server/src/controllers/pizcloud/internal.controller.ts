import { Body, Controller, Get, Post, Query, Req, UseGuards } from '@nestjs/common';
import { InternalJwtGuard } from 'src/pizcloud/internal-auth/internal-jwt.guard';
import { BillingService, EntitlementWebhookBody } from 'src/services/pizcloud/billing.service';

@UseGuards(InternalJwtGuard)
@Controller('internal')
export class InternalController {
  constructor(private readonly billingService: BillingService,) { }


  @Post('entitlements/webhook')
  entitlementsWebhook(@Body() body: EntitlementWebhookBody, @Req() req: any) {
    return this.billingService.handleEntitlementWebhook(body);
  }

  @Get('user-usage')
  async usage(@Query('email') email: string) {
    return this.billingService.getUsageByUserEmail(email);
  }

  @Post('test-webhook')
  testWebhook(@Body() body: any, @Req() req: any) {
    console.log('body', body);
    console.log('req.user', req.user);
    return {
      ok: true,
      calledBy: req.user?.svc,
      jti: req.user?.jti,
      received: body,
    };
  }
}
