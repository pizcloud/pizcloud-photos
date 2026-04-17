import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/features/pizcloud/billing/iap_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

void main() {
  group('IapService replacement mode', () {
    final iapService = IapService(iap: _StubIap());

    test('returns withTimeProration for upgrade', () {
      final mode = iapService.resolveReplacementModeForChange(
        oldProductId: 'storage_100gb_monthly',
        newProductId: 'storage_500gb_monthly',
      );

      expect(mode, ReplacementMode.withTimeProration);
    });

    test('returns deferred for downgrade', () {
      final mode = iapService.resolveReplacementModeForChange(
        oldProductId: 'storage_500gb_monthly',
        newProductId: 'storage_100gb_monthly',
      );

      expect(mode, ReplacementMode.deferred);
    });

    test('returns deferred for same tier but cycle change', () {
      final mode = iapService.resolveReplacementModeForChange(
        oldProductId: 'storage_100gb_monthly',
        newProductId: 'storage_100gb_yearly',
      );

      expect(mode, ReplacementMode.deferred);
    });

    test('returns withTimeProration for same tier and cycle', () {
      final mode = iapService.resolveReplacementModeForChange(
        oldProductId: 'storage_500gb_monthly',
        newProductId: 'storage_500gb_monthly_v2',
      );

      expect(mode, ReplacementMode.withTimeProration);
    });
  });

  group('IapService old subscription selection', () {
    final iapService = IapService(iap: _StubIap());

    test('prefers active entitlement product when provided', () {
      final selected = iapService.selectOldSubscriptionCandidate(
        [
          _purchase(productId: 'storage_1tb_monthly', purchaseTimeMs: 2000, isAutoRenewing: true),
          _purchase(productId: 'storage_100gb_monthly', purchaseTimeMs: 1000, isAutoRenewing: false),
        ],
        targetProductId: 'storage_500gb_monthly',
        activeProductId: 'storage_100gb_monthly',
      );

      expect(selected?.productID, 'storage_100gb_monthly');
    });

    test('prefers higher score before purchase time', () {
      final selected = iapService.selectOldSubscriptionCandidate([
        _purchase(
          productId: 'storage_100gb_monthly',
          purchaseTimeMs: 1000,
          isAutoRenewing: true,
          hasPendingUpdate: false,
        ),
        _purchase(productId: 'storage_1tb_monthly', purchaseTimeMs: 500, isAutoRenewing: true, hasPendingUpdate: true),
      ], targetProductId: 'storage_500gb_monthly');

      expect(selected?.productID, 'storage_1tb_monthly');
    });

    test('uses newest purchase time when scores are tied', () {
      final selected = iapService.selectOldSubscriptionCandidate([
        _purchase(productId: 'storage_100gb_monthly', purchaseTimeMs: 1000, isAutoRenewing: true),
        _purchase(productId: 'storage_1tb_monthly', purchaseTimeMs: 1500, isAutoRenewing: true),
      ], targetProductId: 'storage_500gb_monthly');

      expect(selected?.productID, 'storage_1tb_monthly');
    });

    test('filters out non-matching candidates', () {
      final selected = iapService.selectOldSubscriptionCandidate([
        _purchase(productId: 'storage_500gb_monthly', purchaseTimeMs: 3000, isAutoRenewing: true),
        _purchase(productId: 'random_sku', purchaseTimeMs: 2500, isAutoRenewing: true),
        _purchase(
          productId: 'storage_100gb_monthly',
          purchaseTimeMs: 2000,
          status: PurchaseStatus.pending,
          isAutoRenewing: true,
        ),
        _purchase(productId: 'storage_100gb_yearly', purchaseTimeMs: 1000, isAutoRenewing: false),
      ], targetProductId: 'storage_500gb_monthly');

      expect(selected?.productID, 'storage_100gb_yearly');
    });

    test('returns null when no valid candidate exists', () {
      final selected = iapService.selectOldSubscriptionCandidate([
        _purchase(productId: 'storage_500gb_monthly', purchaseTimeMs: 2000, isAutoRenewing: true),
        _purchase(productId: 'random_sku', purchaseTimeMs: 1000, isAutoRenewing: true),
      ], targetProductId: 'storage_500gb_monthly');

      expect(selected, isNull);
    });
  });
}

GooglePlayPurchaseDetails _purchase({
  required String productId,
  required int purchaseTimeMs,
  PurchaseStatus status = PurchaseStatus.purchased,
  bool isAutoRenewing = true,
  bool hasPendingUpdate = false,
}) {
  final purchase = PurchaseWrapper(
    orderId: 'order_${productId}_$purchaseTimeMs',
    packageName: 'com.example.test',
    purchaseTime: purchaseTimeMs,
    purchaseToken: 'token_${productId}_$purchaseTimeMs',
    signature: 'signature',
    products: [productId],
    isAutoRenewing: isAutoRenewing,
    originalJson: '{}',
    isAcknowledged: true,
    purchaseState: _purchaseStateFromStatus(status),
    pendingPurchaseUpdate: hasPendingUpdate
        ? const PendingPurchaseUpdateWrapper(purchaseToken: 'pending-token', products: ['storage_100gb_monthly'])
        : null,
  );

  return GooglePlayPurchaseDetails(
    purchaseID: purchase.orderId,
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '{}',
      serverVerificationData: purchase.purchaseToken,
      source: 'google_play',
    ),
    transactionDate: purchaseTimeMs.toString(),
    billingClientPurchase: purchase,
    status: status,
  );
}

PurchaseStateWrapper _purchaseStateFromStatus(PurchaseStatus status) {
  if (status == PurchaseStatus.pending) {
    return PurchaseStateWrapper.pending;
  }
  return PurchaseStateWrapper.purchased;
}

class _StubIap extends Fake implements InAppPurchase {}
