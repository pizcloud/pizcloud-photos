import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

class IapService {
  final InAppPurchase _iap = InAppPurchase.instance;
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

  Future<void> buy(ProductDetails p, {String? offerToken}) async {
    if (Platform.isAndroid && p is GooglePlayProductDetails) {
      final googleProduct = p;
      final String? resolvedToken = (offerToken != null && offerToken.isNotEmpty)
          ? offerToken
          : googleProduct.offerToken;

      if (resolvedToken != null && resolvedToken.isNotEmpty) {
        final param = GooglePlayPurchaseParam(productDetails: googleProduct, offerToken: resolvedToken);
        await _iap.buyNonConsumable(purchaseParam: param);
        return;
      }
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
