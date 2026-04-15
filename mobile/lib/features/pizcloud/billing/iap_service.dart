import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

class IapService {
  // final InAppPurchase _iap = InAppPurchase.instance;
  IapService({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  static const List<String> productIdOrder = [
    'storage_50gb_monthly',
    'storage_50gb_yearly',
    'storage_100g_monthly',
    'storage_100g_yearly',
    'storage_500gb_monthly',
    'storage_500gb_yearly',
    'storage_1tb_monthly',
    'storage_1tb_yearly',
    'storage_2tb_monthly',
    'storage_2tb_yearly',
  ];
  static final Set<String> productIds = productIdOrder.toSet();

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<ProductDetailsResponse> queryProducts() => _iap.queryProductDetails(productIds);

  void listen(void Function(PurchaseDetails) onPurchase) {
    _sub?.cancel();
    _sub = _iap.purchaseStream.listen((events) {
      for (final p in events) {
        onPurchase(p);
      }
    });
  }

  bool _looksMonthly(String s) {
    return RegExp(r'(month|monthly|mo|_m$|_monthly$)', caseSensitive: false).hasMatch(s);
  }

  int _planStorageGb(String idOrTitle) {
    final value = idOrTitle.toLowerCase();
    if (value.contains('2tb')) return 2000;
    if (value.contains('1tb')) return 1000;
    if (value.contains('500')) return 500;
    if (value.contains('200')) return 200;
    if (value.contains('100')) return 100;
    if (value.contains('50')) return 50;
    return 0;
  }

  int _purchaseTimeMs(GooglePlayPurchaseDetails purchase) {
    // Prefer Play billing purchaseTime because it is always epoch milliseconds.
    return purchase.billingClientPurchase.purchaseTime;
  }

  // Exposed for regression tests: upgrade/downgrade/cycle-change replacement behavior.
  ReplacementMode resolveReplacementModeForChange({required String oldProductId, required String newProductId}) {
    return _resolveReplacementMode(oldProductId: oldProductId, newProductId: newProductId);
  }

  ReplacementMode _resolveReplacementMode({required String oldProductId, required String newProductId}) {
    final oldSize = _planStorageGb(oldProductId);
    final newSize = _planStorageGb(newProductId);

    if (newSize > oldSize) {
      // Upgrade: apply immediately and prorate the remaining period.
      return ReplacementMode.withTimeProration;
    }

    if (newSize < oldSize) {
      // Downgrade: apply at the next renewal to avoid abrupt quota drops.
      return ReplacementMode.deferred;
    }

    final oldIsMonthly = _looksMonthly(oldProductId);
    final newIsMonthly = _looksMonthly(newProductId);

    if (oldIsMonthly != newIsMonthly) {
      // Same tier but different billing cycle: keep change for next renewal.
      return ReplacementMode.deferred;
    }

    // Same tier / same cycle fallback.
    return ReplacementMode.withTimeProration;
  }

  int _subscriptionCandidateScore(GooglePlayPurchaseDetails purchase, {String? activeProductId}) {
    var score = 0;

    final normalizedActiveId = activeProductId?.trim();
    if (normalizedActiveId != null && normalizedActiveId.isNotEmpty && purchase.productID == normalizedActiveId) {
      // Strong preference for the entitlement product currently active on backend.
      score += 1000;
    }

    if (purchase.billingClientPurchase.isAutoRenewing) {
      // Actively renewing subscriptions are preferred over canceled ones.
      score += 200;
    }

    if (purchase.billingClientPurchase.pendingPurchaseUpdate != null) {
      // Prefer subscriptions currently involved in a pending replacement chain.
      score += 50;
    }

    return score;
  }

  // Exposed for regression tests: deterministic selection of old subscription before replacement.
  GooglePlayPurchaseDetails? selectOldSubscriptionCandidate(
    List<GooglePlayPurchaseDetails> pastPurchases, {
    required String targetProductId,
    String? activeProductId,
  }) {
    final candidates = pastPurchases
        .where(
          (purchase) =>
              productIds.contains(purchase.productID) &&
              purchase.status == PurchaseStatus.purchased &&
              purchase.productID != targetProductId,
        )
        .toList();

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final aScore = _subscriptionCandidateScore(a, activeProductId: activeProductId);
      final bScore = _subscriptionCandidateScore(b, activeProductId: activeProductId);
      final scoreCompare = bScore.compareTo(aScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }

      final aMs = _purchaseTimeMs(a);
      final bMs = _purchaseTimeMs(b);
      return bMs.compareTo(aMs);
    });

    return candidates.first;
  }

  Future<GooglePlayPurchaseDetails?> _findOldSubscriptionForChange(
    String targetProductId, {
    String? activeProductId,
  }) async {
    if (!Platform.isAndroid) return null;

    final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();

    // Inline filter/sort logic for old-subscription selection was implemented directly here.
    // It is extracted into selectOldSubscriptionCandidate(...) for focused unit tests.
    return selectOldSubscriptionCandidate(
      response.pastPurchases,
      targetProductId: targetProductId,
      activeProductId: activeProductId,
    );
  }

  // Future<void> buy(ProductDetails p, {String? offerToken}) async {
  Future<void> buy(ProductDetails p, {String? offerToken, String? activeProductId}) async {
    if (Platform.isAndroid && p is GooglePlayProductDetails) {
      final googleProduct = p;
      final String? resolvedToken = (offerToken != null && offerToken.isNotEmpty)
          ? offerToken
          : googleProduct.offerToken;
      ChangeSubscriptionParam? changeSubscriptionParam;

      try {
        final oldPurchase = await _findOldSubscriptionForChange(googleProduct.id, activeProductId: activeProductId);
        if (oldPurchase != null) {
          changeSubscriptionParam = ChangeSubscriptionParam(
            oldPurchaseDetails: oldPurchase,
            replacementMode: _resolveReplacementMode(
              oldProductId: oldPurchase.productID,
              newProductId: googleProduct.id,
            ),
          );
        }
      } catch (_) {
        // Best-effort only. If this fails, still proceed with a normal purchase flow.
      }

      if (resolvedToken != null && resolvedToken.isNotEmpty) {
        // final param = GooglePlayPurchaseParam(productDetails: googleProduct, offerToken: resolvedToken);
        final param = GooglePlayPurchaseParam(
          productDetails: googleProduct,
          offerToken: resolvedToken,
          changeSubscriptionParam: changeSubscriptionParam,
        );
        await _iap.buyNonConsumable(purchaseParam: param);
        return;
      }

      final param = GooglePlayPurchaseParam(
        productDetails: googleProduct,
        changeSubscriptionParam: changeSubscriptionParam,
      );
      await _iap.buyNonConsumable(purchaseParam: param);
      return;
    }

    final param = PurchaseParam(productDetails: p);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> complete(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) await _iap.completePurchase(p);
  }

  void dispose() => _sub?.cancel();
}
