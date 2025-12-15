// server/src/controllers/pizcloud/referral.controller.ts
import { BadRequestException, Body, Controller, Get, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { Authenticated } from 'src/middleware/auth.guard';
import { ReferralService } from 'src/services/pizcloud/referral.service';

@Controller('referral')
export class ReferralController {
  constructor(private readonly referralService: ReferralService) { }

  @Get('summary')
  @Authenticated()
  async getSummary(@Query('email') email: string | undefined, @Req() req: Request) {
    let effectiveEmail = (email || '').trim();

    const userFromReq = (req as any)?.user;
    if (!effectiveEmail && userFromReq?.email) {
      effectiveEmail = String(userFromReq.email);
    }

    if (!effectiveEmail) {
      throw new BadRequestException('Email is required to get referral summary');
    }

    return this.referralService.fetchSummaryFromPServer(effectiveEmail);
  }

  @Post('apply-code')
  @Authenticated()
  async applyCode(
    @Body() body: { code?: string; email?: string },
    @Req() req: Request,
  ) {
    const code = (body?.code || '').trim();
    let effectiveEmail = (body?.email || '').trim();

    const userFromReq = (req as any)?.user;
    if (!effectiveEmail && userFromReq?.email) {
      effectiveEmail = String(userFromReq.email);
    }

    if (!code) {
      throw new BadRequestException('Referral code is required');
    }

    if (!effectiveEmail) {
      throw new BadRequestException('Email is required to apply referral code');
    }

    return this.referralService.applyCode(effectiveEmail, code);
  }

  @Get('payout-method')
  @Authenticated()
  async getPayoutMethod(@Query('email') email: string | undefined, @Req() req: Request) {
    let effectiveEmail = (email || '').trim();

    const userFromReq = (req as any)?.user;
    if (!effectiveEmail && userFromReq?.email) {
      effectiveEmail = String(userFromReq.email);
    }

    if (!effectiveEmail) {
      throw new BadRequestException('Email is required to get payout method');
    }

    return this.referralService.getPayoutMethod(effectiveEmail);
  }

  @Post('payout-method')
  @Authenticated()
  async savePayoutMethod(
    @Body()
    body: {
      email?: string;
      method?: 'bank' | 'paypal';
      bankName?: string;
      bankAccountNumber?: string;
      bankAccountHolderName?: string;
      paypalEmail?: string;
      paypalFullName?: string;
    },
    @Req() req: Request,
  ) {
    let effectiveEmail = (body?.email || '').trim();
    const userFromReq = (req as any)?.user;
    if (!effectiveEmail && userFromReq?.email) {
      effectiveEmail = String(userFromReq.email);
    }

    if (!effectiveEmail) {
      throw new BadRequestException('Email is required to save payout method');
    }

    return this.referralService.savePayoutMethod({
      email: effectiveEmail,
      method: body?.method,
      bankName: body?.bankName,
      bankAccountNumber: body?.bankAccountNumber,
      bankAccountHolderName: body?.bankAccountHolderName,
      paypalEmail: body?.paypalEmail,
      paypalFullName: body?.paypalFullName,
    });
  }

  @Get('withdrawals')
  @Authenticated()
  async listWithdrawals(
    @Query('email') email: string | undefined,
    @Query('page') page: string | undefined,
    @Query('limit') limit: string | undefined,
    @Query('status') status: string | undefined,
    @Req() req: Request,
  ) {
    let effectiveEmail = (email || '').trim();

    const userFromReq = (req as any)?.user;
    if (!effectiveEmail && userFromReq?.email) {
      effectiveEmail = String(userFromReq.email);
    }

    if (!effectiveEmail) {
      throw new BadRequestException('Email is required to list withdrawals');
    }

    return this.referralService.listWithdrawals({
      email: effectiveEmail,
      page,
      limit,
      status,
    });
  }

  @Post('withdrawals')
  @Authenticated()
  async requestWithdrawal(
    @Body()
    body: {
      email?: string;
      amount?: number;
      currency?: string;
      method?: 'bank' | 'paypal';
    },
    @Req() req: Request,
  ) {
    let effectiveEmail = (body?.email || '').trim();
    const userFromReq = (req as any)?.user;
    if (!effectiveEmail && userFromReq?.email) {
      effectiveEmail = String(userFromReq.email);
    }

    if (!effectiveEmail) {
      throw new BadRequestException('Email is required to request withdrawal');
    }

    return this.referralService.requestWithdrawal({
      email: effectiveEmail,
      amount: body?.amount,
      currency: body?.currency,
      method: body?.method,
    });
  }
}
