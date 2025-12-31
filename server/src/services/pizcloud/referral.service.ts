// // server/src/services/pizcloud/referral.service.ts
// import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
// import axios from 'axios';
// import https from 'https';

// @Injectable()
// export class ReferralService {
//   private readonly logger = new Logger(ReferralService.name);

//   async fetchSummaryFromPServer(email: string) {
//     const base = process.env.PIZCLOUD_BASE_URL;
//     if (!base) {
//       this.logger.error(
//         'fetchSummaryFromPServer: missing PIZCLOUD_BASE_URL',
//       );
//       throw new UnauthorizedException('Referral upstream is not configured');
//     }

//     // Upstream currently exposes /referral/summary
//     const url = `${base.replace(/\/+$/, '')}/referral/summary`;
//     const internalKey = process.env.PIZCLOUD_INTERNAL_KEY;

//     if (!internalKey) {
//       this.logger.error(
//         'fetchSummaryFromPServer: missing internal key (PIZCLOUD_INTERNAL_KEY)',
//       );
//       throw new UnauthorizedException('Referral internal key is not configured');
//     }
//     console.log('url', url);
//     try {
//       const timeout = Number(process.env.P_SERVER_TIMEOUT_MS ?? 10000);

//       const { data } = await axios.get(url, {
//         params: { email },
//         headers: {
//           'Content-Type': 'application/json',
//           'x-internal-key': internalKey,
//           'x-user-email': email,
//         },
//         timeout,
//       });
//       return data;
//     } catch (error: any) {
//       this.logger.error(
//         `fetchSummaryFromPServer: failed for email=${email}, url=${url}`,
//         error?.response?.status
//           ? `${error.response.status} ${error.response.statusText}`
//           : error?.message || error,
//       );
//       throw error;
//     }
//   }

//   async applyCode(email: string, code: string) {
//     const base = process.env.PIZCLOUD_BASE_URL;
//     if (!base) {
//       this.logger.error('applyCode: missing PIZCLOUD_BASE_URL');
//       throw new UnauthorizedException('Referral upstream is not configured');
//     }

//     const url = `${base.replace(/\/+$/, '')}/referral/apply-code`;
//     const internalKey = process.env.PIZCLOUD_INTERNAL_KEY;

//     if (!internalKey) {
//       this.logger.error('applyCode: missing internal key (PIZCLOUD_INTERNAL_KEY)');
//       throw new UnauthorizedException('Referral internal key is not configured');
//     }

//     try {
//       const timeout = Number(process.env.P_SERVER_TIMEOUT_MS ?? 10000);
//       const httpsAgent =
//         process.env.P_SERVER_INSECURE_TLS === 'true'
//           ? new https.Agent({ rejectUnauthorized: false })
//           : undefined;

//       const { data } = await axios.post(
//         url,
//         { email, code },
//         {
//           headers: {
//             'Content-Type': 'application/json',
//             'x-internal-key': internalKey,
//             'x-user-email': email,
//           },
//           timeout,
//           httpsAgent,
//         },
//       );

//       return data;
//     } catch (error: any) {
//       this.logger.error(
//         `applyCode: failed for email=${email}, url=${url}`,
//         error?.response?.status
//           ? `${error.response.status} ${error.response.statusText}`
//           : error?.message || error,
//       );
//       throw error;
//     }
//   }

//   async getPayoutMethod(email: string) {
//     const base = process.env.PIZCLOUD_BASE_URL;
//     if (!base) {
//       this.logger.error('getPayoutMethod: missing PIZCLOUD_BASE_URL');
//       throw new UnauthorizedException('Referral upstream is not configured');
//     }

//     const url = `${base.replace(/\/+$/, '')}/referral/payout-method`;
//     const internalKey = process.env.PIZCLOUD_INTERNAL_KEY;

//     if (!internalKey) {
//       this.logger.error(
//         'getPayoutMethod: missing internal key (PIZCLOUD_INTERNAL_KEY)',
//       );
//       throw new UnauthorizedException('Referral internal key is not configured');
//     }

//     try {
//       const timeout = Number(process.env.P_SERVER_TIMEOUT_MS ?? 10000);
//       const httpsAgent =
//         process.env.P_SERVER_INSECURE_TLS === 'true'
//           ? new https.Agent({ rejectUnauthorized: false })
//           : undefined;

//       const { data } = await axios.get(url, {
//         params: { email },
//         headers: {
//           'Content-Type': 'application/json',
//           'x-internal-key': internalKey,
//           'x-user-email': email,
//         },
//         timeout,
//         httpsAgent,
//       });

//       return data;
//     } catch (error: any) {
//       this.logger.error(
//         `getPayoutMethod: failed for email=${email}, url=${url}`,
//         error?.response?.status
//           ? `${error.response.status} ${error.response.statusText}`
//           : error?.message || error,
//       );
//       throw error;
//     }
//   }

//   async savePayoutMethod(input: {
//     email: string;
//     method?: 'bank' | 'paypal';
//     bankName?: string;
//     bankAccountNumber?: string;
//     bankAccountHolderName?: string;
//     paypalEmail?: string;
//     paypalFullName?: string;
//   }) {
//     const base = process.env.PIZCLOUD_BASE_URL;
//     if (!base) {
//       this.logger.error('savePayoutMethod: missing PIZCLOUD_BASE_URL');
//       throw new UnauthorizedException('Referral upstream is not configured');
//     }

//     const url = `${base.replace(/\/+$/, '')}/referral/payout-method`;
//     const internalKey = process.env.PIZCLOUD_INTERNAL_KEY;

//     if (!internalKey) {
//       this.logger.error(
//         'savePayoutMethod: missing internal key (PIZCLOUD_INTERNAL_KEY)',
//       );
//       throw new UnauthorizedException('Referral internal key is not configured');
//     }

//     try {
//       const timeout = Number(process.env.P_SERVER_TIMEOUT_MS ?? 10000);
//       const httpsAgent =
//         process.env.P_SERVER_INSECURE_TLS === 'true'
//           ? new https.Agent({ rejectUnauthorized: false })
//           : undefined;

//       const { data } = await axios.post(
//         url,
//         input,
//         {
//           headers: {
//             'Content-Type': 'application/json',
//             'x-internal-key': internalKey,
//             'x-user-email': input.email,
//           },
//           timeout,
//           httpsAgent,
//         },
//       );

//       return data;
//     } catch (error: any) {
//       this.logger.error(
//         `savePayoutMethod: failed for email=${input.email}, url=${url}`,
//         error?.response?.status
//           ? `${error.response.status} ${error.response.statusText}`
//           : error?.message || error,
//       );
//       throw error;
//     }
//   }

//   async listWithdrawals(params: {
//     email: string;
//     page?: string;
//     limit?: string;
//     status?: string;
//   }) {
//     const base = process.env.PIZCLOUD_BASE_URL;
//     if (!base) {
//       this.logger.error('listWithdrawals: missing PIZCLOUD_BASE_URL');
//       throw new UnauthorizedException('Referral upstream is not configured');
//     }

//     const url = `${base.replace(/\/+$/, '')}/referral/withdrawals`;
//     const internalKey = process.env.PIZCLOUD_INTERNAL_KEY;

//     if (!internalKey) {
//       this.logger.error(
//         'listWithdrawals: missing internal key (PIZCLOUD_INTERNAL_KEY)',
//       );
//       throw new UnauthorizedException('Referral internal key is not configured');
//     }

//     try {
//       const timeout = Number(process.env.P_SERVER_TIMEOUT_MS ?? 10000);
//       const httpsAgent =
//         process.env.P_SERVER_INSECURE_TLS === 'true'
//           ? new https.Agent({ rejectUnauthorized: false })
//           : undefined;

//       const { data } = await axios.get(url, {
//         params: {
//           email: params.email,
//           page: params.page,
//           limit: params.limit,
//           status: params.status,
//         },
//         headers: {
//           'Content-Type': 'application/json',
//           'x-internal-key': internalKey,
//           'x-user-email': params.email,
//         },
//         timeout,
//         httpsAgent,
//       });

//       return data;
//     } catch (error: any) {
//       this.logger.error(
//         `listWithdrawals: failed for email=${params.email}, url=${url}`,
//         error?.response?.status
//           ? `${error.response.status} ${error.response.statusText}`
//           : error?.message || error,
//       );
//       throw error;
//     }
//   }

//   async requestWithdrawal(params: {
//     email: string;
//     amount?: number;
//     currency?: string;
//     method?: 'bank' | 'paypal';
//   }) {
//     const base = process.env.PIZCLOUD_BASE_URL;
//     if (!base) {
//       this.logger.error('requestWithdrawal: missing PIZCLOUD_BASE_URL');
//       throw new UnauthorizedException('Referral upstream is not configured');
//     }

//     const url = `${base.replace(/\/+$/, '')}/referral/withdrawals`;
//     const internalKey = process.env.PIZCLOUD_INTERNAL_KEY;

//     if (!internalKey) {
//       this.logger.error(
//         'requestWithdrawal: missing internal key (PIZCLOUD_INTERNAL_KEY)',
//       );
//       throw new UnauthorizedException('Referral internal key is not configured');
//     }

//     try {
//       const timeout = Number(process.env.P_SERVER_TIMEOUT_MS ?? 10000);
//       const httpsAgent =
//         process.env.P_SERVER_INSECURE_TLS === 'true'
//           ? new https.Agent({ rejectUnauthorized: false })
//           : undefined;

//       const { data } = await axios.post(
//         url,
//         {
//           email: params.email,
//           amount: params.amount,
//           currency: params.currency,
//           method: params.method,
//         },
//         {
//           headers: {
//             'Content-Type': 'application/json',
//             'x-internal-key': internalKey,
//             'x-user-email': params.email,
//           },
//           timeout,
//           httpsAgent,
//         },
//       );

//       return data;
//     } catch (error: any) {
//       this.logger.error(
//         `requestWithdrawal: failed for email=${params.email}, url=${url}`,
//         error?.response?.status
//           ? `${error.response.status} ${error.response.statusText}`
//           : error?.message || error,
//       );
//       throw error;
//     }
//   }
// }
