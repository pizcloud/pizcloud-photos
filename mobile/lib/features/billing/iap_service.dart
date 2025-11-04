import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

class IapService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  static const productIds = <String>{
    'storage_100g_monthly',
    'storage_100g_yearly',
    'storage_200g_monthly',
    'storage_200g_yearly',
    'storage_2tb_monthly',
    'storage_2tb_yearly',
  };

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

  Future<void> buy(ProductDetails p) async {
    final param = PurchaseParam(productDetails: p);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> complete(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) await _iap.completePurchase(p);
  }

  void dispose() => _sub?.cancel();
}
