import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'dart:io';
import 'package:immich_mobile/config/app_config.dart';
import 'package:immich_mobile/features/pizcloud/billing/android_offer_utils.dart';
// import 'package:immich_mobile/features/pizcloud/billing/billing_controller.dart';
import 'package:immich_mobile/providers/pizcloud/billing.provider.dart';
import 'package:immich_mobile/features/pizcloud/billing/iap_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

/// ===============================================================
///                FAKE MODE (UI DEMO WITHOUT IAP)
/// ===============================================================
const bool kUseFakeProducts = !kReleaseMode && AppConfig.enableBillingFakeProducts;

class FakeProduct {
  final String id;
  final String title;
  final String description;
  final String price;
  const FakeProduct(this.id, this.title, this.description, this.price);
}

const List<FakeProduct> kFakeProducts = [
  FakeProduct('storage_50gb_monthly', 'Basic', '50 GB cloud storage billed monthly', '\$0.2'),
  FakeProduct('storage_50gb_yearly', 'Basic', '50 GB cloud storage billed yearly', '\$2,4'),
  FakeProduct('storage_100g_monthly', 'Pro1', '100 GB cloud storage billed monthly', '\$0.4'),
  FakeProduct('storage_100g_yearly', 'Pro1', '100 GB cloud storage billed yearly', '\$4.8'),
  FakeProduct('storage_500gb_monthly', 'Pro2', '500 GB cloud storage billed monthly', '\$5'),
  FakeProduct('storage_500gb_yearly', 'Pro2', '500 GB cloud storage billed yearly', '\$50'),
  FakeProduct('storage_1tb_monthly', 'Pro3', '1 TB cloud storage billed monthly', '\$10'),
  FakeProduct('storage_1tb_yearly', 'Pro3', '1 TB cloud storage billed yearly', '\$120'),
  FakeProduct('storage_2tb_monthly', 'Premium', '2 TB cloud storage billed monthly', '\$12'),
  FakeProduct('storage_2tb_yearly', 'Premium', '2 TB cloud storage billed yearly', '\$144'),
];

/// ===============================================================
///                HELPERS & MODELS
/// ===============================================================
enum BillingPeriod { monthly, yearly }

bool _looksMonthly(String s) => RegExp(r'(month|monthly|mo|_m$|_monthly$)', caseSensitive: false).hasMatch(s);
bool _looksYearly(String s) =>
    RegExp(r'(year|yearly|annual|annually|yr|_y$|_yearly$)', caseSensitive: false).hasMatch(s);

Color _bannerColor(String s, BuildContext context) {
  switch (s) {
    case 'warn':
      return Colors.amber.shade200;
    case 'critical':
      return Colors.orange.shade300;
    case 'blocked':
      return Colors.red.shade300;
    default:
      return Theme.of(context).colorScheme.secondaryContainer;
  }
}

DateTime? _parseEntitlementExpiry(dynamic raw) {
  if (raw is num) {
    final ms = raw.toInt();
    if (ms > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
  }
  if (raw is String) {
    final ms = int.tryParse(raw);
    if (ms != null && ms > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
  }
  return null;
}

String _formatShortDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

Color _entitlementBannerColor(String status, BuildContext context) {
  switch (status) {
    case 'canceled_pending_expiry':
      return const Color.fromARGB(255, 229, 121, 32);
    case 'in_grace_period':
      return const Color.fromARGB(255, 216, 112, 27);
    case 'on_hold':
    case 'paused':
      return const Color.fromARGB(255, 185, 95, 21);
    case 'expired':
    case 'revoked':
    case 'pending_purchase_canceled':
      return Colors.red.shade300;
    default:
      return Theme.of(context).colorScheme.secondaryContainer;
  }
}

String _entitlementStatusTitle(String status) {
  switch (status) {
    case 'canceled_pending_expiry':
      return 'subscription.entitlement_title_canceled_pending_expiry'.tr();
    case 'in_grace_period':
      return 'subscription.entitlement_title_in_grace_period'.tr();
    case 'on_hold':
      return 'subscription.entitlement_title_on_hold'.tr();
    case 'paused':
      return 'subscription.entitlement_title_paused'.tr();
    case 'expired':
      return 'subscription.entitlement_title_expired'.tr();
    case 'revoked':
      return 'subscription.entitlement_title_revoked'.tr();
    case 'pending_purchase_canceled':
      return 'subscription.entitlement_title_pending_purchase_canceled'.tr();
    case 'pending':
      return 'subscription.entitlement_title_pending'.tr();
    default:
      return 'subscription.entitlement_title_default'.tr();
  }
}

String _entitlementStatusMessage(String status, DateTime? expiresAt) {
  switch (status) {
    case 'canceled_pending_expiry':
      if (expiresAt != null) {
        return 'subscription.entitlement_message_canceled_pending_expiry_with_date'.tr(
          namedArgs: {'date': _formatShortDate(expiresAt)},
        );
      }
      return 'subscription.entitlement_message_canceled_pending_expiry'.tr();
    case 'in_grace_period':
      return 'subscription.entitlement_message_in_grace_period'.tr();
    case 'on_hold':
      return 'subscription.entitlement_message_on_hold'.tr();
    case 'paused':
      return 'subscription.entitlement_message_paused'.tr();
    case 'expired':
      return 'subscription.entitlement_message_expired'.tr();
    case 'revoked':
      return 'subscription.entitlement_message_revoked'.tr();
    case 'pending_purchase_canceled':
      return 'subscription.entitlement_message_pending_purchase_canceled'.tr();
    case 'pending':
      return 'subscription.entitlement_message_pending'.tr();
    default:
      return 'subscription.entitlement_message_default'.tr();
  }
}

void _snack(BuildContext c, String msg) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

List<String> _featuresFor(String idOrTitle) {
  final s = idOrTitle.toLowerCase();
  final common = [
    'billing.file_sync_across_devices'.tr(),
    'billing.multi_device_sync'.tr(),
    'billing.advanced_file_sharing'.tr(),
  ];
  if (s.contains('2tb') || s.contains('premium')) {
    return ['billing.storage_2tb'.tr(), ...common];
  }
  if (s.contains('1tb') || s.contains('pro3')) {
    return ['billing.storage_1tb'.tr(), ...common];
  }
  if (s.contains('500') || s.contains('pro2')) {
    return ['billing.storage_500gb'.tr(), ...common];
  }
  if (s.contains('100') || s.contains('pro1')) {
    return ['billing.storage_100gb'.tr(), ...common];
  }
  return ['billing.storage_50gb'.tr(), ...common];
}

bool _isMostPopular(String idOrTitle) {
  final s = idOrTitle.toLowerCase();
  return s.contains('100') || s.contains('pro1') || s.contains('100g');
}

String _planShortTitle(String title, String id) {
  final normalizedId = id.trim().toLowerCase();

  const idToPlanName = <String, String>{
    'storage_50gb_monthly': 'Basic',
    'storage_50gb_yearly': 'Basic',
    'storage_100g_monthly': 'Pro1',
    'storage_100g_yearly': 'Pro1',
    'storage_500gb_monthly': 'Pro2',
    'storage_500gb_yearly': 'Pro2',
    'storage_1tb_monthly': 'Pro3',
    'storage_1tb_yearly': 'Pro3',
    'storage_2tb_monthly': 'Premium',
    'storage_2tb_yearly': 'Premium',
  };

  final planByExactId = idToPlanName[normalizedId];
  if (planByExactId != null) return planByExactId;

  final sizeGb = _planStorageGb(normalizedId);
  if (sizeGb >= 2000) return 'Premium';
  if (sizeGb >= 1000) return 'Pro3';
  if (sizeGb >= 500) return 'Pro2';
  if (sizeGb >= 100) return 'Pro1';

  final t = title.trim().toLowerCase();

  if (t.contains('premium') || t.contains('2tb') || t.contains('2 tb') || t.contains('2000')) {
    return 'Premium';
  }
  if (t.contains('pro3') || t.contains('1tb') || t.contains('1 tb') || t.contains('1000')) {
    return 'Pro3';
  }
  if (t.contains('pro2') || t.contains('500')) {
    return 'Pro2';
  }
  if (t.contains('pro1') || t.contains('100')) {
    return 'Pro1';
  }
  if (t.contains('basic') || t.contains('50')) {
    return 'Basic';
  }

  return 'Basic';
}

bool _isLargePlan(String idOrTitleOrDesc) {
  final s = idOrTitleOrDesc.toLowerCase();
  return s.contains('500gb') ||
      s.contains('500 gb') ||
      s.contains('1tb') ||
      s.contains('1 tb') ||
      s.contains('1000gb') ||
      s.contains('1000 gb') ||
      s.contains('2tb') ||
      s.contains('2 tb') ||
      s.contains('2000gb') ||
      s.contains('2000 gb') ||
      s.contains('50 gb') ||
      s.contains('50gb') ||
      s.contains('100 g') ||
      s.contains('100g');
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

bool _isEntitlementActiveForPurchaseGuard(String? status) {
  if (status == null || status.isEmpty) {
    // Legacy payloads may omit status. If productId exists, treat as active.
    return true;
  }

  switch (status) {
    case 'expired':
    case 'revoked':
    case 'pending_purchase_canceled':
      return false;
    default:
      return true;
  }
}

bool _isPurchaseLockedByEntitlementStatus(String? status) {
  if (status == null || status.isEmpty) {
    return false;
  }

  switch (status) {
    case 'paused':
    case 'on_hold':
      return true;
    default:
      return false;
  }
}

String _ctaButtonLabel({
  required PlanDisplay selectedPlan,
  required String? activeProductId,
  required bool hasActiveEntitlement,
}) {
  if (!hasActiveEntitlement || activeProductId == null || activeProductId.isEmpty) {
    return 'subscription.buy_now'.tr();
  }

  final selectedSize = _planStorageGb(selectedPlan.id);
  final activeSize = _planStorageGb(activeProductId);

  if (selectedSize > activeSize) {
    return 'subscription.cta_upgrade_now'.tr();
  }

  if (selectedSize < activeSize) {
    return 'subscription.cta_downgrade_next_cycle'.tr();
  }

  final selectedMonthly = selectedPlan.isMonthly;
  final activeMonthly = _looksMonthly(activeProductId);

  if (selectedMonthly != activeMonthly) {
    return 'subscription.cta_change_billing_cycle'.tr();
  }

  return 'subscription.buy_now'.tr();
}

String _androidOfferDisplayPrice(AndroidOfferInfo info) {
  final offer = info.offer;
  if (offer == null || offer.pricingPhases.isEmpty) return info.product.price;

  // Prefer the last non-zero phase to avoid showing a free trial as the price.
  for (var i = offer.pricingPhases.length - 1; i >= 0; i -= 1) {
    final phase = offer.pricingPhases[i];
    if (phase.priceAmountMicros > 0) return phase.formattedPrice;
  }

  return offer.pricingPhases.last.formattedPrice;
}

class PlanDisplay {
  final String id;
  final String title; // Basic / Pro / Premium
  final String price; // "$9.99"
  final bool isMonthly;
  final List<String> features;
  final bool highlighted; // Most Popular
  final ProductDetails? raw; // null if fake

  final bool referralDiscountApplied;
  final String? offerToken;

  const PlanDisplay({
    required this.id,
    required this.title,
    required this.price,
    required this.isMonthly,
    required this.features,
    required this.highlighted,
    required this.raw,
    this.referralDiscountApplied = false,
    this.offerToken,
  });
}

/// ===============================================================
///                UI: PLAN CARD
/// ===============================================================
class _PlanCard extends StatelessWidget {
  final PlanDisplay data;
  final BillingPeriod period;
  final bool selected;
  final bool disabled;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.data,
    required this.period,
    required this.selected,
    this.disabled = false,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor = data.highlighted
        ? theme.colorScheme.primary
        : (selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant);
    final cardBg = isDark ? theme.colorScheme.surface : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: data.highlighted || selected ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            offset: const Offset(0, 8),
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + price row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(data.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),

                            const SizedBox(width: 8),

                            if (data.highlighted)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'billing.most_popular'.tr(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                            if (selected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'selected'.tr(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        if (data.referralDiscountApplied) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  context.platformIcon(material: Icons.local_offer, cupertino: CupertinoIcons.tag),
                                  size: 14,
                                  color: Colors.green[700],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '-30%',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(data.price, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        period == BillingPeriod.monthly ? '/${'month'.tr()}' : '/${'year'.tr()}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Features
              ...data.features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        context.platformIcon(
                          material: Icons.check_circle,
                          cupertino: CupertinoIcons.check_mark_circled_solid,
                        ),
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f, style: theme.textTheme.bodyMedium?.copyWith(height: 1.2))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (data.referralDiscountApplied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        context.platformIcon(material: Icons.info_outline, cupertino: CupertinoIcons.info),
                        size: 16,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'referral.you_are_receiving_discount_on_this_plan',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green[700], height: 1.2),
                        ).tr(),
                      ),
                    ],
                  ),
                ),
              // Select button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: data.highlighted
                    ? ElevatedButton(
                        onPressed: disabled ? null : onSelect,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(disabled ? 'selected'.tr() : 'billing.select_plan'.tr()),
                      )
                    : OutlinedButton(
                        onPressed: disabled ? null : onSelect,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(disabled ? 'selected'.tr() : 'billing.select_plan'.tr()),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
///                PAGE
/// ===============================================================
@RoutePage()
class BillingPage extends HookConsumerWidget {
  const BillingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final state = ref.watch(billingControllerProvider) as dynamic;
    final ctl = ref.read(billingControllerProvider.notifier);

    final entitlement = state.entitlement as Map<String, dynamic>?;
    final usage = state.usage as Map<String, dynamic>?;
    final referral = state.referral as Map<String, dynamic>?;
    final rawEntitlementStatus = entitlement?['entitlementStatus'];
    final entitlementStatus = rawEntitlementStatus is String ? rawEntitlementStatus.trim().toLowerCase() : null;
    final rawActiveProductId = entitlement?['productId'];
    final activeProductId = rawActiveProductId is String ? rawActiveProductId.trim() : null;
    final hasActiveEntitlement =
        activeProductId != null &&
        activeProductId.isNotEmpty &&
        _isEntitlementActiveForPurchaseGuard(entitlementStatus);
    final isPurchaseLockedByStatus = _isPurchaseLockedByEntitlementStatus(entitlementStatus);
    final entitlementExpiry = _parseEntitlementExpiry(entitlement?['expiresAtMs']);
    final showEntitlementBanner =
        entitlementStatus != null && entitlementStatus.isNotEmpty && entitlementStatus != 'active';

    // Check if the user has a valid referral discount
    bool hasReferralDiscount = false;
    DateTime? discountEndAt;

    final referrer = referral?['referrer'] as Map<String, dynamic>?;
    if (referrer != null) {
      final endStr = referrer['discountEndAt'] as String?;
      if (endStr != null) {
        discountEndAt = DateTime.tryParse(endStr);
        if (discountEndAt != null && discountEndAt.isAfter(DateTime.now())) {
          hasReferralDiscount = true;
        }
      }
    }

    final bool referralStillValid = hasReferralDiscount;

    // Toggle Monthly / Yearly (default: Monthly)
    final period = useState(BillingPeriod.monthly);

    // Selected plan (for sticky CTA)
    final selectedPlan = useState<PlanDisplay?>(null);
    final isBuying = useState(false);

    // Real products if any
    final List<ProductDetails> realProducts = (state.products as List<ProductDetails>? ?? const []);

    // Decide fake mode
    final bool isFakeMode = kUseFakeProducts && (realProducts.isEmpty || state.error != null);

    // Build unified items
    final List<PlanDisplay> items = [];
    if (isFakeMode) {
      for (final p in kFakeProducts) {
        final bool largePlan = _isLargePlan('${p.id} ${p.title} ${p.description}');
        items.add(
          PlanDisplay(
            id: p.id,
            title: _planShortTitle(p.title, p.id),
            price: p.price,
            isMonthly: _looksMonthly(p.id) || _looksMonthly(p.title),
            features: _featuresFor('${p.id} ${p.title}'),
            highlighted: _isMostPopular('${p.id} ${p.title}'),
            raw: null,
            referralDiscountApplied: referralStillValid && largePlan,
            offerToken: null,
          ),
        );
      }
    } else {
      if (Platform.isAndroid) {
        // ANDROID: Use offer token, select the referral-30 offer if it is still valid
        final androidOffers = extractAndroidOffers(realProducts, preferReferral: referralStillValid);

        final Map<String, AndroidOfferInfo> selectedByKey = {};

        AndroidOfferInfo pickForKey(String key, AndroidOfferInfo candidate) {
          final current = selectedByKey[key];

          if (referralStillValid) {
            if (candidate.isReferralOffer) return candidate;
            return current ?? candidate;
          } else {
            if (candidate.isReferralOffer) {
              return current ?? candidate;
            } else {
              return candidate;
            }
          }
        }

        for (final info in androidOffers) {
          final p = info.product;
          final isM = _looksMonthly(p.id) || _looksMonthly(p.title) || _looksMonthly(p.description);
          final isY = _looksYearly(p.id) || _looksYearly(p.title) || _looksYearly(p.description);
          final resolvedMonthly = isM || (!isM && !isY);

          final key = '${p.id}#${resolvedMonthly ? 'm' : 'y'}';
          final chosen = pickForKey(key, info);
          selectedByKey[key] = chosen;
        }

        for (final entry in selectedByKey.entries) {
          final p = entry.value.product;
          final isM = _looksMonthly(p.id) || _looksMonthly(p.title) || _looksMonthly(p.description);
          final isY = _looksYearly(p.id) || _looksYearly(p.title) || _looksYearly(p.description);
          final resolvedMonthly = isM || (!isM && !isY);

          final bool largePlan = _isLargePlan('${p.id} ${p.title} ${p.description}');

          items.add(
            PlanDisplay(
              id: p.id,
              title: _planShortTitle(p.title, p.id),
              // OLD:
              // price: p.price,
              price: _androidOfferDisplayPrice(entry.value),
              isMonthly: resolvedMonthly,
              features: _featuresFor('${p.id} ${p.title} ${p.description}'),
              highlighted: _isMostPopular('${p.id} ${p.title}'),
              raw: p,
              referralDiscountApplied: referralStillValid && largePlan,
              offerToken: entry.value.offerToken,
            ),
          );
        }
      } else {
        for (final p in realProducts) {
          final isM = _looksMonthly(p.id) || _looksMonthly(p.title) || _looksMonthly(p.description);
          final isY = _looksYearly(p.id) || _looksYearly(p.title) || _looksYearly(p.description);
          final resolvedMonthly = isM || (!isM && !isY);

          final bool largePlan = _isLargePlan('${p.id} ${p.title} ${p.description}');

          items.add(
            PlanDisplay(
              id: p.id,
              title: _planShortTitle(p.title, p.id),
              price: p.price,
              isMonthly: resolvedMonthly,
              features: _featuresFor('${p.id} ${p.title} ${p.description}'),
              highlighted: _isMostPopular('${p.id} ${p.title}'),
              raw: p,
              referralDiscountApplied: referralStillValid && largePlan,
              offerToken: null,
            ),
          );
        }
      }
    }

    // Filter by current period
    final filtered = items.where((e) => period.value == BillingPeriod.monthly ? e.isMonthly : !e.isMonthly).toList();

    final orderIndex = <String, int>{};
    for (var i = 0; i < IapService.productIdOrder.length; i += 1) {
      orderIndex[IapService.productIdOrder[i]] = i;
    }

    filtered.sort((a, b) => (orderIndex[a.id] ?? 1 << 30).compareTo(orderIndex[b.id] ?? 1 << 30));

    useEffect(() {
      selectedPlan.value = null;
      return null;
    }, [period.value]);

    useEffect(() {
      if (isPurchaseLockedByStatus) {
        selectedPlan.value = null;
      }
      return null;
    }, [isPurchaseLockedByStatus]);

    useEffect(() {
      Future.microtask(ctl.refreshUsage);
      return null;
    }, const []);

    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed) {
        Future.microtask(ctl.refreshUsage);
      }
    });

    final selectedIsCurrentPlan =
        selectedPlan.value != null && hasActiveEntitlement && activeProductId == selectedPlan.value!.id;
    final currentProductIdForDisplay = activeProductId ?? '';

    // final showCta = selectedPlan.value != null;
    final showCta = selectedPlan.value != null && !selectedIsCurrentPlan && !isPurchaseLockedByStatus;

    final ctaButtonText = selectedPlan.value == null
        ? 'subscription.buy_now'.tr()
        : _ctaButtonLabel(
            selectedPlan: selectedPlan.value!,
            activeProductId: activeProductId,
            hasActiveEntitlement: hasActiveEntitlement,
          );

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('choose_your_plan').tr(),
        material: (_, __) => MaterialAppBarData(centerTitle: true),
      ),
      // Sticky CTA
      material: (_, __) => MaterialScaffoldData(
        bottomNavBar: showCta
            ? SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                        color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Summary line
                      Text(
                        'subscription.continue_with'.tr(
                          namedArgs: {
                            'plan': selectedPlan.value!.title,
                            'price': selectedPlan.value!.price,
                            'period': period.value == BillingPeriod.monthly
                                ? 'subscription.period_month'.tr()
                                : 'subscription.period_year'.tr(),
                          },
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isBuying.value
                              ? null
                              : () async {
                                  final plan = selectedPlan.value;
                                  if (plan == null) return;

                                  if (isPurchaseLockedByStatus) {
                                    _snack(context, 'subscription.purchase_locked_manage_subscription'.tr());
                                    return;
                                  }

                                  if (hasActiveEntitlement && activeProductId == plan.id) {
                                    _snack(context, 'subscription.current_plan_already_active'.tr());
                                    return;
                                  }

                                  isBuying.value = true;
                                  try {
                                    if (plan.raw != null) {
                                      // Real purchase
                                      await ref
                                          .read(billingControllerProvider.notifier)
                                          // .buy(plan.raw!, offerToken: plan.offerToken);
                                          .buy(
                                            plan.raw!,
                                            offerToken: plan.offerToken,
                                            activeProductId: activeProductId,
                                          );
                                    } else {
                                      try {
                                        await ref.read(billingControllerProvider.notifier).fakeBuy(plan.id);
                                        _snack(context, 'Pretend buy (sent to server): ${plan.id} (${plan.price})');
                                      } catch (e) {
                                        _snack(context, 'Fake buy failed: $e');
                                      }

                                      // Fake purchase
                                      // _snack(context, 'Pretend buy: ${plan.id} (${plan.price})');
                                    }
                                  } finally {
                                    isBuying.value = false;
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          // child: const Text('subscription.buy_now').tr(),
                          child: Text(isBuying.value ? 'please_wait'.tr() : ctaButtonText),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), // extra bottom for CTA
          children: [
            if (showEntitlementBanner) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _entitlementBannerColor('canceled_pending_expiry', context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _entitlementStatusTitle(entitlementStatus),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _entitlementStatusMessage(entitlementStatus, entitlementExpiry),
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.25),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (isPurchaseLockedByStatus) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  'subscription.purchase_locked_manage_subscription'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (usage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bannerColor(usage['state'] as String, context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'subscription.summary'.tr(
                        namedArgs: {
                          'used': usage['used_gb'].toString(),
                          'limit': usage['limit_gb'].toString(),
                          'percent': usage['percent'].toString(),
                        },
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: ((usage['percent'] as num) / 100).clamp(0, 1).toDouble()),
                    if (usage['state'] == 'warn')
                      Padding(padding: const EdgeInsets.only(top: 6), child: const Text('subscription.warn').tr()),
                    if (usage['state'] == 'critical')
                      Padding(padding: const EdgeInsets.only(top: 6), child: const Text('subscription.critical').tr()),
                    if (usage['state'] == 'blocked')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('subscription.blocked'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (hasActiveEntitlement) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'subscription.current_plan_banner'.tr(
                    namedArgs: {
                      'plan': _planShortTitle('', currentProductIdForDisplay),
                      'period': _looksMonthly(currentProductIdForDisplay)
                          ? 'subscription.period_monthly'.tr()
                          : 'subscription.period_yearly'.tr(),
                    },
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Header icon + title + sub
            Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    context.platformIcon(material: Icons.lock_outline, cupertino: CupertinoIcons.lock),
                    size: 28,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'subscription.upgrade_title'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'subscription.upgrade_subtitle'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Monthly / Yearly segmented control
            Row(
              children: [
                Expanded(
                  child: _PeriodTab(
                    text: 'subscription.period_monthly'.tr(),
                    selected: period.value == BillingPeriod.monthly,
                    onTap: () => period.value = BillingPeriod.monthly,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PeriodTab(
                    text: 'subscription.period_yearly'.tr(),
                    hintRight: 'subscription.save_20'.tr(),
                    selected: period.value == BillingPeriod.yearly,
                    onTap: () => period.value = BillingPeriod.yearly,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(state.error!, style: const TextStyle(color: Colors.red)),
              ),

            // Plan cards
            for (final it in filtered)
              Builder(
                builder: (_) {
                  final isCurrentPlan = hasActiveEntitlement && activeProductId == it.id;
                  return _PlanCard(
                    data: it,
                    period: period.value,
                    // selected: selectedPlan.value?.id == it.id,
                    selected: selectedPlan.value?.id == it.id || isCurrentPlan,
                    disabled: isCurrentPlan || isPurchaseLockedByStatus,
                    onSelect: () {
                      if (isPurchaseLockedByStatus) {
                        _snack(context, 'subscription.purchase_locked_manage_subscription'.tr());
                        return;
                      }

                      if (isCurrentPlan) {
                        _snack(context, 'subscription.current_plan_already_active'.tr());
                        return;
                      }
                      selectedPlan.value = it;
                    },
                  );
                },
              ),

            const SizedBox(height: 8),

            // Why choose box
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'subscription.why_title'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  _WhyRow(
                    icon: context.platformIcon(
                      material: Icons.verified_user_outlined,
                      cupertino: CupertinoIcons.checkmark_shield,
                    ),
                    title: 'subscription.why_secure_title'.tr(),
                    subtitle: 'subscription.why_secure_sub'.tr(),
                  ),
                  const SizedBox(height: 10),
                  _WhyRow(
                    icon: context.platformIcon(
                      material: Icons.sync_outlined,
                      cupertino: CupertinoIcons.arrow_2_circlepath,
                    ),
                    title: 'subscription.why_sync_title'.tr(),
                    subtitle: 'subscription.why_sync_sub'.tr(),
                  ),
                  const SizedBox(height: 10),
                  // _WhyRow(
                  //   icon: Icons.history_outlined,
                  //   title: 'subscription.why_history_title'.tr(),
                  //   subtitle: 'subscription.why_history_sub'.tr(),
                  // ),
                  // const SizedBox(height: 10),
                  // Row(
                  //   children: [
                  //     Icon(Icons.verified, size: 18, color: Colors.green[600]),
                  //     const SizedBox(width: 6),
                  //     Text(
                  //       'subscription.guarantee'.tr(),
                  //       style: theme.textTheme.bodyMedium?.copyWith(
                  //         color: Colors.green[700],
                  //         fontWeight: FontWeight.w600,
                  //       ),
                  //     ),
                  //   ],
                  // ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Restore purchases
            // Center(
            //   child: TextButton(
            //     onPressed: () {
            //       if (isFakeMode) {
            //         _snack(context, 'subscription.pretend_restore'.tr());
            //       } else {
            //         ctl.restore();
            //       }
            //     },
            //     child: Text('subscription.restore_purchases'.tr()),
            //   ),
            // ),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () async {
                  final activeProductId = entitlement?['productId'] as String?;
                  await _openManageSubscription(context, ref, productId: activeProductId);
                },
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('subscription.manage_subscription'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openManageSubscription(BuildContext context, WidgetRef ref, {String? productId}) async {
    final cfg = ref.read(billingConfigProvider);

    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    Uri primary;
    Uri? fallback;

    if (isAndroid) {
      if (productId != null && productId.isNotEmpty) {
        primary = Uri.parse(
          'https://play.google.com/store/account/subscriptions?sku=$productId&package=${cfg.androidPackageName}',
        );
        fallback = Uri.parse('https://play.google.com/store/account/subscriptions?package=${cfg.androidPackageName}');
      } else {
        primary = Uri.parse('https://play.google.com/store/account/subscriptions?package=${cfg.androidPackageName}');
      }
    } else if (isIOS) {
      primary = Uri.parse('itms-apps://apps.apple.com/account/subscriptions');
      fallback = Uri.parse('https://apps.apple.com/account/subscriptions');
    } else {
      primary = Uri.parse('https://play.google.com/store/account/subscriptions');
    }

    final ok = await launchUrl(primary, mode: LaunchMode.externalApplication);
    if (!ok && fallback != null) {
      final ok2 = await launchUrl(fallback, mode: LaunchMode.externalApplication);
      if (!ok2) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open subscription manager.')));
      }
    } else if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open subscription manager.')));
    }
  }
}

/// ===============================================================
///                SUB-WIDGETS
/// ===============================================================
class _PeriodTab extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final String? hintRight;
  const _PeriodTab({required this.text, required this.selected, required this.onTap, this.hintRight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : theme.colorScheme.surface,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
            if (hintRight != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hintRight!,
                  style: theme.textTheme.labelSmall?.copyWith(color: Colors.green[700], fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WhyRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _WhyRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
