// lib/features/pizcloud/billing/android_offer_utils.dart

import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

class AndroidOfferInfo {
  final GooglePlayProductDetails product;

  final SubscriptionOfferDetailsWrapper? offer;

  final bool isReferralOffer;

  final String? offerToken;

  AndroidOfferInfo({
    required this.product,
    required this.offer,
    required this.isReferralOffer,
    required this.offerToken,
  });

  @override
  String toString() {
    return 'AndroidOfferInfo(productId=${product.id}, '
        'price=${product.price}, '
        'isReferralOffer=$isReferralOffer, '
        'offerToken=$offerToken)';
  }
}

List<AndroidOfferInfo> extractAndroidOffers(List<ProductDetails> products, {bool preferReferral = false}) {
  if (!Platform.isAndroid) return const [];

  final result = <AndroidOfferInfo>[];

  for (final p in products) {
    if (p is! GooglePlayProductDetails) continue;

    final gp = p;
    final idx = gp.subscriptionIndex;
    final offers = gp.productDetails.subscriptionOfferDetails;

    SubscriptionOfferDetailsWrapper? offer;
    String? offerToken;

    if (offers != null && offers.isNotEmpty) {
      // Prefer referral offer if requested and available.
      if (preferReferral) {
        for (final candidate in offers) {
          if (candidate.offerTags.contains('referral-30')) {
            offer = candidate;
            break;
          }
        }
      }

      // Fallback to subscriptionIndex if referral not chosen.
      if (offer == null && idx != null && idx >= 0 && idx < offers.length) {
        offer = offers[idx];
      }

      // Final fallback to the first offer (most common base plan).
      offer ??= offers.first;

      offerToken = offer.offerIdToken;
    } else {
      offerToken = gp.offerToken;
    }

    final tags = offer?.offerTags ?? const <String>[];
    final isReferral = tags.contains('referral-30'); // tag set on Play Console

    result.add(AndroidOfferInfo(product: gp, offer: offer, isReferralOffer: isReferral, offerToken: offerToken));
  }

  return result;
}
