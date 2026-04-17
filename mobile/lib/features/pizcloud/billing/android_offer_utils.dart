// lib/features/pizcloud/billing/android_offer_utils.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
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

const String _referralOfferBaseTag = 'referral-30';
final RegExp _referralOfferCyclesTag = RegExp(r'^referral-30-cycles(?:-(\d+))?$');

bool _looksMonthly(String value) {
  return RegExp(r'(month|monthly|mo|_m$|_monthly$)', caseSensitive: false).hasMatch(value);
}

bool _looksYearly(String value) {
  return RegExp(r'(year|yearly|annual|annually|yr|_y$|_yearly$)', caseSensitive: false).hasMatch(value);
}

bool _isMonthlyProduct(ProductDetails product) {
  final isM = _looksMonthly(product.id) || _looksMonthly(product.title) || _looksMonthly(product.description);
  final isY = _looksYearly(product.id) || _looksYearly(product.title) || _looksYearly(product.description);
  return isM || (!isM && !isY);
}

@visibleForTesting
bool hasReferralOfferTag(Iterable<String> offerTags) {
  for (final raw in offerTags) {
    final tag = raw.trim().toLowerCase();
    if (tag == _referralOfferBaseTag || _referralOfferCyclesTag.hasMatch(tag)) {
      return true;
    }
  }
  return false;
}

@visibleForTesting
int? parseReferralCyclesTag(Iterable<String> offerTags) {
  for (final raw in offerTags) {
    final tag = raw.trim().toLowerCase();
    final match = _referralOfferCyclesTag.firstMatch(tag);
    if (match != null && match.groupCount >= 1) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
  }
  return null;
}

@visibleForTesting
SubscriptionOfferDetailsWrapper? selectReferralOfferForRemainingCycles(
  List<SubscriptionOfferDetailsWrapper> offers, {
  required int targetCycles,
}) {
  if (targetCycles <= 0) {
    return null;
  }

  SubscriptionOfferDetailsWrapper? nearestLower;
  var nearestLowerCycles = -1;

  for (final offer in offers) {
    final cycles = parseReferralCyclesTag(offer.offerTags);
    if (cycles == null) {
      continue;
    }
    if (cycles == targetCycles) {
      return offer;
    }
    if (cycles < targetCycles && cycles > nearestLowerCycles) {
      nearestLower = offer;
      nearestLowerCycles = cycles;
    }
  }

  return nearestLower;
}

@visibleForTesting
SubscriptionOfferDetailsWrapper? selectFirstReferralOffer(List<SubscriptionOfferDetailsWrapper> offers) {
  for (final offer in offers) {
    if (hasReferralOfferTag(offer.offerTags)) {
      return offer;
    }
  }
  return null;
}

List<AndroidOfferInfo> extractAndroidOffers(
  List<ProductDetails> products, {
  bool preferReferral = false,
  int? targetReferralCyclesMonthly,
  int? targetReferralCyclesYearly,
}) {
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
        final targetCycles = _isMonthlyProduct(gp) ? targetReferralCyclesMonthly : targetReferralCyclesYearly;
        if (targetCycles != null) {
          offer = selectReferralOfferForRemainingCycles(offers, targetCycles: targetCycles);
        }

        // OLD:
        // for (final candidate in offers) {
        //   if (candidate.offerTags.contains('referral-30')) {
        //     offer = candidate;
        //     break;
        //   }
        // }
        offer ??= selectFirstReferralOffer(offers);
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
    // `referral-30` is backward-compatible. New strategy uses `referral-30-cycles-N`.
    final isReferral = hasReferralOfferTag(tags);

    result.add(AndroidOfferInfo(product: gp, offer: offer, isReferralOffer: isReferral, offerToken: offerToken));
  }

  return result;
}
