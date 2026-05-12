import { Body, Controller, Get, Post, Query, Req, UseGuards } from '@nestjs/common';
import { EntitlementWebhookDto } from 'src/dtos/entitlement-webhook.dto';
import { InternalUserSelfDeleteRequestDto } from 'src/dtos/internal-user-delete.dto';
import { InternalJwtGuard } from 'src/pizcloud/internal-auth/internal-jwt.guard';
import { BillingService } from 'src/services/pizcloud/billing.service';
import { InternalUserDeleteService } from 'src/services/pizcloud/internal-user-delete.service';
import { InternalUserSyncService } from 'src/services/pizcloud/internal-user-sync.service';

@UseGuards(InternalJwtGuard)
@Controller('internal')
export class InternalController {
  constructor(
    private readonly billingService: BillingService,
    private readonly internalUserDeleteService: InternalUserDeleteService,
    private readonly internalUserSyncService: InternalUserSyncService,
  ) { }

  @Post('entitlements/webhook')
  entitlementsWebhook(@Body() body: EntitlementWebhookDto, @Req() req: any) {
    return this.billingService.handleEntitlementWebhook(body);
  }

  @Get('user-usage')
  async usage(@Query('email') email: string) {
    return this.billingService.getUsageByUserEmail(email);
  }

  @Get('user-sync-overview')
  async userSyncOverview(@Query('email') email?: string, @Query('userId') userId?: string) {
    return this.internalUserSyncService.getUserSyncOverview({ email, userId });
  }

  @Post('users/self-delete')
  async selfDeleteUser(@Body() body: InternalUserSelfDeleteRequestDto) {
    console.log('selfDeleteUser', body);
    return this.internalUserDeleteService.selfDelete(body);
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
