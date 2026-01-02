// web/src/lib/models/pizcloud/billing.ts
export type BillingInterval = 'month' | 'year';
export type PlanTier = 'basic' | 'pro' | 'premium';

export interface StoragePlan {
  id: string;
  name: string;
  tier: PlanTier;
  description: string;
  storageGb: number;
  price: number;
  currency: string;
  interval: BillingInterval;
  recommended?: boolean;
}
