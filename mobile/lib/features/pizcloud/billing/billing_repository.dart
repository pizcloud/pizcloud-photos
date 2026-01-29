import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'entitlement_api_client.dart';
import 'ios_receipt_channel.dart';
import 'iap_service.dart';
import 'ios_promotional_offer.dart';

class BillingRepository {
  BillingRepository({required this.api, required this.iap, required this.packageName});

  final EntitlementApiClient api;
  final IapService iap;
  final String packageName;

  Future<Map<String, dynamic>?> loadEntitlement() => api.getEntitlements();
  Future<Map<String, dynamic>> loadUsage() => api.getUsage();

  Future<Map<String, dynamic>?> loadReferralSummary() => api.getReferralSummary();

  // Future<void> purchase(ProductDetails p, {String? offerToken}) => iap.buy(p, offerToken: offerToken);
  Future<void> purchase(ProductDetails p, {String? offerToken, String? iosOfferId}) async {
    if (Platform.isIOS && iosOfferId != null && iosOfferId.isNotEmpty) {
      final applicationUserName = api.userEntity.id;

      final sig = await api.getIosPromotionalOfferSignature(
        productId: p.id,
        offerId: iosOfferId,
        applicationUserName: applicationUserName,
      );

      await iap.buy(p, offerToken: offerToken, iosOffer: sig, applicationUserName: applicationUserName);
      return;
    }

    await iap.buy(p, offerToken: offerToken);
  }

  Future<void> handlePurchase(PurchaseDetails p) async {
    if (p.status == PurchaseStatus.pending) return;
    if (p.status == PurchaseStatus.error) return;

    if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
      final productId = p.productID;
      if (Platform.isIOS) {
        final receipt = await IosReceiptChannel.getReceiptBase64();
        await api.verifyIosReceipt(productId: productId, receiptBase64: receipt);
      } else {
        final token = p.verificationData.serverVerificationData; // purchaseToken
        await api.verifyAndroidPurchase(productId: productId, purchaseToken: token, packageName: packageName);
      }
      await iap.complete(p);
    }
  }

  Future<void> fakePurchase(String productId) async {
    await api.notifyVerifiedPurchase(productId: productId, platform: Platform.isAndroid ? 'android' : 'ios');
  }
}
