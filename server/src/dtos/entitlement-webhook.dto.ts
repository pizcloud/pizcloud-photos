import { Allow } from 'class-validator';

export type EntitlementStatus =
  | 'active'
  | 'in_grace_period'
  | 'on_hold'
  | 'paused'
  | 'canceled_pending_expiry'
  | 'expired'
  | 'revoked'
  | 'pending'
  | 'pending_purchase_canceled';

export type EntitlementPendingPeriod = 'monthly' | 'yearly';

export class EntitlementWebhookDto {
  // Keep DTO permissive to avoid breaking existing internal webhook integrations.
  @Allow()
  userId!: string;

  @Allow()
  email!: string;

  @Allow()
  productId!: string;

  @Allow()
  planCode!: string;

  @Allow()
  storageLimitGb!: number;

  @Allow()
  mlTier?: 'free' | 'basic' | 'pro1' | 'pro2' | 'pro3' | 'premium';

  @Allow()
  seats?: number;

  @Allow()
  shareEnabled?: boolean;

  @Allow()
  signature!: string;

  @Allow()
  schemaVersion?: 2;

  @Allow()
  eventId?: string;

  @Allow()
  eventTimeMs?: number;

  @Allow()
  source?: 'google_play_rtdn' | 'app_store_server_notification';

  @Allow()
  platform?: 'android' | 'ios';

  @Allow()
  entitlementStatus?: EntitlementStatus;

  @Allow()
  autoRenewEnabled?: boolean;

  @Allow()
  expiresAtMs?: number;

  @Allow()
  cancelReason?: 'user' | 'system' | 'developer' | 'replacement' | 'unknown';

  @Allow()
  providerNotificationType?: number;

  @Allow()
  providerSubscriptionState?: string;

  @Allow()
  purchaseToken?: string;

  @Allow()
  linkedPurchaseToken?: string;

  @Allow()
  paymentSyncState?: 'awaiting_charge';

  @Allow()
  purchaseLocked?: boolean;

  @Allow()
  purchaseLockReason?: 'pause_scheduled' | 'paused' | 'on_hold' | 'none';

  @Allow()
  purchaseLockObservedAtMs?: number;

  @Allow()
  purchaseLockEffectiveAtMs?: number;

  @Allow()
  pendingProductId?: string;

  @Allow()
  pendingPeriod?: EntitlementPendingPeriod;
}

