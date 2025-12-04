import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

class AndroidOfferInfo {
  final GooglePlayProductDetails product;
  final SubscriptionOfferDetailsWrapper? offer;
  final bool isReferralOffer;

  AndroidOfferInfo({required this.product, required this.offer, required this.isReferralOffer});
}

List<AndroidOfferInfo> extractAndroidOffers(List<ProductDetails> products) {
  if (!Platform.isAndroid) return const [];

  final result = <AndroidOfferInfo>[];

  for (final p in products) {
    if (p is! GooglePlayProductDetails) continue;

    final gp = p;
    final idx = gp.subscriptionIndex;
    final offers = gp.productDetails.subscriptionOfferDetails;

    SubscriptionOfferDetailsWrapper? offer;
    if (idx != null && offers != null && idx >= 0 && idx < offers.length) {
      offer = offers[idx];
    }

    final tags = offer?.offerTags ?? const <String>[];
    final isReferral = tags.contains('referral-30'); // tag set on Play Console

    result.add(AndroidOfferInfo(product: gp, offer: offer, isReferralOffer: isReferral));
  }

  return result;
}
