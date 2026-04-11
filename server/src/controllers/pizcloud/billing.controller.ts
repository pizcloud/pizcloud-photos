// server/src/controllers/pizcloud/billing.controller.ts
import { Controller, Get, UnauthorizedException } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto';
import { Auth, Authenticated } from 'src/middleware/auth.guard';
import { BillingService } from 'src/services/pizcloud/billing.service';

@Controller('billing')
export class BillingController {
  constructor(private readonly billingService: BillingService,) { }


  // GET /api/billing/usage
  @Get('usage')
  @Authenticated()
  async usage(@Auth() auth: AuthDto) {
    return this.billingService.getUsage(auth);
  }

  // GET /api/billing/entitlements
  @Get('entitlements')
  @Authenticated()
  async getEntitlement(@Auth() auth: AuthDto) {
    const userId = auth.user.id;
    if (!userId) {
      throw new UnauthorizedException('No authenticated user');
    }

    return this.billingService.getEntitlement(userId);
  }
}
