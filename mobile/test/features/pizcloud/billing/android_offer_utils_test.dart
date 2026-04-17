import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/features/pizcloud/billing/android_offer_utils.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

void main() {
  group('Android offer tags', () {
    test('detects referral tags for base and cycles variants', () {
      expect(hasReferralOfferTag(const ['referral-30']), isTrue);
      expect(hasReferralOfferTag(const ['referral-30-cycles']), isTrue);
      expect(hasReferralOfferTag(const ['referral-30-cycles-6']), isTrue);
      expect(hasReferralOfferTag(const ['other-tag']), isFalse);
    });

    test('parses cycle count from referral cycles tag', () {
      expect(parseReferralCyclesTag(const ['referral-30-cycles']), isNull);
      expect(parseReferralCyclesTag(const ['referral-30-cycles-1']), 1);
      expect(parseReferralCyclesTag(const [' REFERRAL-30-CYCLES-12 ']), 12);
      expect(parseReferralCyclesTag(const ['referral-30']), isNull);
      expect(parseReferralCyclesTag(const ['referral-30-cycles-x']), isNull);
    });
  });

  group('Android offer selection by remaining cycles', () {
    test('selects exact cycle match when available', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_1', tags: const ['referral-30-cycles-1']),
        _offer(token: 'offer_3', tags: const ['referral-30-cycles-3']),
        _offer(token: 'offer_6', tags: const ['referral-30-cycles-6']),
      ], targetCycles: 3);

      expect(selected?.offerIdToken, 'offer_3');
    });

    test('falls back to nearest lower cycle when exact not available', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_1', tags: const ['referral-30-cycles-1']),
        _offer(token: 'offer_3', tags: const ['referral-30-cycles-3']),
      ], targetCycles: 5);

      expect(selected?.offerIdToken, 'offer_3');
    });

    test('returns null when only higher cycles exist', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_6', tags: const ['referral-30-cycles-6']),
        _offer(token: 'offer_12', tags: const ['referral-30-cycles-12']),
      ], targetCycles: 5);

      expect(selected, isNull);
    });
  });
}

SubscriptionOfferDetailsWrapper _offer({required String token, required List<String> tags}) {
  return SubscriptionOfferDetailsWrapper(
    basePlanId: 'base_plan',
    offerId: token,
    offerTags: tags,
    offerIdToken: token,
    pricingPhases: const [
      PricingPhaseWrapper(
        billingCycleCount: 1,
        billingPeriod: 'P1M',
        formattedPrice: '\$1.99',
        priceAmountMicros: 1990000,
        priceCurrencyCode: 'USD',
        recurrenceMode: RecurrenceMode.finiteRecurring,
      ),
    ],
  );
}
