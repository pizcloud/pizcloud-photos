export type BillingPeriod = 'monthly' | 'yearly';
export type MlTier = 'basic' | 'pro1' | 'pro2' | 'pro3' | 'premium';

export type BillingProduct = {
  id: string; // product id (sku)
  planCode: string;
  storageLimitGb: number;
  mlTier: MlTier;
  seats: number;
  shareEnabled: boolean;
  period: BillingPeriod;
  priceUsd: number;
  priceVnd?: number;
};

export type BankCode = 'VCB' | 'ACB';

export type BankAccountInfo = {
  code: BankCode;
  name: string;
  accountNumber: string;
  accountName: string;
  branch?: string | null;
};

export type BillingOrderStatus = 'PENDING' | 'PAID' | 'CANCELLED' | 'EXPIRED';

export type BillingOrder = {
  id: string;
  status: BillingOrderStatus;
  productId: string;
  amountVnd: number;
  currency: 'VND';
  transferNote: string;
  bank: BankAccountInfo;
  expiresAt: string; // ISO
  createdAt: string; // ISO

  updatedAt?: string;
  paidAt?: string | null;
  cancelledAt?: string | null;
  cancelReason?: string | null;
};
