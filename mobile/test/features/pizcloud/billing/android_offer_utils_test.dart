import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/features/pizcloud/billing/android_offer_utils.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

void main() {
  group('Android offer ids', () {
    test('detects referral offers by offerId', () {
      expect(hasReferralOfferId('referral-30'), isTrue);
      expect(hasReferralOfferId('referral-30-cycles'), isTrue);
      expect(hasReferralOfferId('referral-30-cycles-9'), isTrue);
      expect(hasReferralOfferId('other-offer'), isFalse);
      expect(hasReferralOfferId(null), isFalse);
    });

    test('parses cycle count from offerId', () {
      expect(parseReferralCyclesOfferId('referral-30-cycles-1'), 1);
      expect(parseReferralCyclesOfferId(' REFERRAL-30-CYCLES-12 '), 12);
      expect(parseReferralCyclesOfferId('referral-30-cycles'), isNull);
      expect(parseReferralCyclesOfferId('referral-30'), isNull);
      expect(parseReferralCyclesOfferId('referral-30-cycles-x'), isNull);
    });
  });

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
    test('prioritizes offerId cycle over tag cycle', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_conflict', offerId: 'referral-30-cycles-3', tags: const ['referral-30-cycles-1']),
      ], targetCycles: 3);

      expect(selected?.offerIdToken, 'offer_conflict');
      expect(parseReferralCyclesOfferDetails(selected!), 3);
    });

    test('selects exact cycle match using offerId when tags are missing', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_1', offerId: 'referral-30-cycles-1', tags: const []),
        _offer(token: 'offer_4', offerId: 'referral-30-cycles-4', tags: const []),
      ], targetCycles: 4);

      expect(selected?.offerIdToken, 'offer_4');
    });

    test('selects exact cycle match when available', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_1', offerId: 'non-referral-1', tags: const ['referral-30-cycles-1']),
        _offer(token: 'offer_3', offerId: 'non-referral-3', tags: const ['referral-30-cycles-3']),
        _offer(token: 'offer_6', offerId: 'non-referral-6', tags: const ['referral-30-cycles-6']),
      ], targetCycles: 3);

      expect(selected?.offerIdToken, 'offer_3');
    });

    test('falls back to nearest lower cycle when exact not available', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_1', offerId: 'non-referral-a', tags: const ['referral-30-cycles-1']),
        _offer(token: 'offer_3', offerId: 'non-referral-b', tags: const ['referral-30-cycles-3']),
      ], targetCycles: 5);

      expect(selected?.offerIdToken, 'offer_3');
    });

    test('returns null when only higher cycles exist', () {
      final selected = selectReferralOfferForRemainingCycles([
        _offer(token: 'offer_6', offerId: 'non-referral-c', tags: const ['referral-30-cycles-6']),
        _offer(token: 'offer_12', offerId: 'non-referral-d', tags: const ['referral-30-cycles-12']),
      ], targetCycles: 5);

      expect(selected, isNull);
    });
  });
}

SubscriptionOfferDetailsWrapper _offer({required String token, required String offerId, required List<String> tags}) {
  return SubscriptionOfferDetailsWrapper(
    basePlanId: 'base_plan',
    offerId: offerId,
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
