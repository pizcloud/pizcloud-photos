import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'billing_state.dart';
import 'billing_repository.dart';
import 'iap_service.dart';

class BillingController extends StateNotifier<BillingState> {
  BillingController({required this.repo, required this.iap}) : super(BillingState.initial());

  final BillingRepository repo;
  final IapService iap;
  Timer? _expiryRefreshTimer;

  int? _toMs(dynamic value) {
    if (value == null) {
      return null;
    }
    final n = value is int ? value : int.tryParse(value.toString());
    if (n == null || n <= 0) {
      return null;
    }
    return n;
  }

  void _scheduleExpiryRefresh(Map<String, dynamic>? status) {
    _expiryRefreshTimer?.cancel();
    if (status == null) {
      return;
    }

    final cancelAtPeriodEnd = status['cancelAtPeriodEnd'] == true;
    final expiresAtMs = _toMs(status['expiresAtMs']);
    if (!cancelAtPeriodEnd || expiresAtMs == null) {
      return;
    }

    final nowMs = _toMs(status['serverNowMs']) ?? DateTime.now().millisecondsSinceEpoch;
    final delayMs = expiresAtMs - nowMs + 2000;
    if (delayMs <= 0) {
      _expiryRefreshTimer = Timer(const Duration(seconds: 30), () async {
        await refreshSubscriptionStatus();
        await refreshUsage();
      });
      return;
    }

    // Cap to 24h so very long waits are re-evaluated on resume/next refresh.
    const maxDelayMs = 24 * 60 * 60 * 1000;
    final boundedDelay = delayMs > maxDelayMs ? maxDelayMs : delayMs;

    _expiryRefreshTimer = Timer(Duration(milliseconds: boundedDelay), () async {
      await refreshSubscriptionStatus();
      await refreshUsage();
    });
  }

  Future<void> _refreshRemoteData({List<ProductDetails>? products, String? error, bool loading = false}) async {
    final entFuture = repo.loadEntitlement();
    final usageFuture = repo.loadUsage();
    final referralFuture = repo.loadReferralSummary();
    final statusFuture = repo.loadSubscriptionStatus();

    final ent = await entFuture;
    final usage = await usageFuture;
    final referral = await referralFuture;
    final subscriptionStatus = await statusFuture;

    _scheduleExpiryRefresh(subscriptionStatus);

    state = state.copy(
      loading: loading,
      products: products ?? state.products,
      entitlement: ent,
      subscriptionStatus: subscriptionStatus,
      usage: usage,
      referral: referral,
      error: error,
    );
  }

  Future<void> init() async {
    try {
      final ok = await iap.isAvailable();
      if (!ok) {
        await _refreshRemoteData(products: const [], error: 'In-App Purchases not available', loading: false);
        return;
      }

      iap.listen((p) async {
        try {
          await repo.handlePurchase(p);
          await _refreshRemoteData(loading: false);
        } catch (e) {
          state = state.copy(error: '$e');
        }
      });

      final resp = await iap.queryProducts();
      if (resp.error != null) {
        await _refreshRemoteData(error: resp.error!.message, loading: false);
      } else {
        await _refreshRemoteData(products: resp.productDetails, loading: false);
      }
    } catch (e) {
      state = state.copy(loading: false, error: '$e');
    }
  }

  // OLD:
  // Future<void> buy(ProductDetails p) => repo.purchase(p);
  Future<void> buy(ProductDetails p, {String? offerToken}) => repo.purchase(p, offerToken: offerToken);

  Future<void> refreshUsage() async {
    try {
      final usageFuture = repo.loadUsage();
      final referralFuture = repo.loadReferralSummary();
      final usage = await usageFuture;
      final referral = await referralFuture;
      state = state.copy(usage: usage, referral: referral);
    } catch (e) {
      state = state.copy(error: '$e');
    }
  }

  Future<void> refreshSubscriptionStatus() async {
    try {
      final subscriptionStatus = await repo.loadSubscriptionStatus();
      _scheduleExpiryRefresh(subscriptionStatus);
      state = state.copy(subscriptionStatus: subscriptionStatus);
    } catch (e) {
      state = state.copy(error: '$e');
    }
  }

  Future<void> restore() => iap.restore();

  Future<void> fakeBuy(String productId) async {
    try {
      await repo.fakePurchase(productId);
      await _refreshRemoteData(loading: false);
    } catch (e) {
      state = state.copy(error: '$e');
    }
  }

  @override
  void dispose() {
    _expiryRefreshTimer?.cancel();
    iap.dispose();
    super.dispose();
  }
}
