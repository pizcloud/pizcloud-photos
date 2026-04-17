@Tags(['widget'])
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/features/pizcloud/billing/billing_controller.dart';
import 'package:immich_mobile/features/pizcloud/billing/billing_repository.dart';
import 'package:immich_mobile/features/pizcloud/billing/billing_state.dart';
import 'package:immich_mobile/features/pizcloud/billing/iap_service.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/pages/settings/pizcloud/billing_page.dart';
import 'package:immich_mobile/providers/pizcloud/billing.provider.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

void main() {
  EasyLocalization.logger.enableBuildModes = [];

  testWidgets('shows upgrade CTA when selecting a higher plan', (tester) async {
    _setLargeTestSurface(tester);

    final controller = _TestBillingController(
      initialState: BillingState(
        loading: false,
        products: [
          _product(id: 'storage_100gb_monthly', title: 'Pro1', price: '\$0.4'),
          _product(id: 'storage_500gb_monthly', title: 'Pro2', price: '\$5'),
        ],
        entitlement: {'productId': 'storage_100gb_monthly', 'entitlementStatus': 'active'},
      ),
    );

    await _pumpBillingPage(tester, controller);

    final selectPlanText = 'billing.select_plan'.tr();
    expect(find.text(selectPlanText), findsOneWidget);

    await tester.tap(find.text(selectPlanText));
    await tester.pumpAndSettle();

    expect(find.text('subscription.cta_upgrade_now'.tr()), findsOneWidget);
  });

  testWidgets('shows downgrade CTA when selecting a lower plan', (tester) async {
    _setLargeTestSurface(tester);

    final controller = _TestBillingController(
      initialState: BillingState(
        loading: false,
        products: [
          _product(id: 'storage_100gb_monthly', title: 'Pro1', price: '\$0.4'),
          _product(id: 'storage_500gb_monthly', title: 'Pro2', price: '\$5'),
        ],
        entitlement: {'productId': 'storage_500gb_monthly', 'entitlementStatus': 'active'},
      ),
    );

    await _pumpBillingPage(tester, controller);

    final selectPlanText = 'billing.select_plan'.tr();
    expect(find.text(selectPlanText), findsOneWidget);

    await tester.tap(find.text(selectPlanText));
    await tester.pumpAndSettle();

    expect(find.text('subscription.cta_downgrade_next_cycle'.tr()), findsOneWidget);
  });

  testWidgets('locks purchase actions when entitlement status is paused', (tester) async {
    _setLargeTestSurface(tester);

    final controller = _TestBillingController(
      initialState: BillingState(
        loading: false,
        products: [
          _product(id: 'storage_100gb_monthly', title: 'Pro1', price: '\$0.4'),
          _product(id: 'storage_500gb_monthly', title: 'Pro2', price: '\$5'),
        ],
        entitlement: {'productId': 'storage_500gb_monthly', 'entitlementStatus': 'paused'},
      ),
    );

    await _pumpBillingPage(tester, controller);

    expect(find.text('subscription.purchase_locked_manage_subscription'.tr()), findsOneWidget);
    expect(find.text('billing.select_plan'.tr()), findsNothing);
    expect(find.text('subscription.cta_upgrade_now'.tr()), findsNothing);
    expect(find.text('subscription.cta_downgrade_next_cycle'.tr()), findsNothing);
  });

  testWidgets('locks purchase actions when entitlement status is on_hold', (tester) async {
    _setLargeTestSurface(tester);

    final controller = _TestBillingController(
      initialState: BillingState(
        loading: false,
        products: [
          _product(id: 'storage_100gb_monthly', title: 'Pro1', price: '\$0.4'),
          _product(id: 'storage_500gb_monthly', title: 'Pro2', price: '\$5'),
        ],
        entitlement: {'productId': 'storage_500gb_monthly', 'entitlementStatus': 'on_hold'},
      ),
    );

    await _pumpBillingPage(tester, controller);

    expect(find.text('subscription.purchase_locked_manage_subscription'.tr()), findsOneWidget);
    expect(find.text('billing.select_plan'.tr()), findsNothing);
    expect(find.text('subscription.cta_upgrade_now'.tr()), findsNothing);
    expect(find.text('subscription.cta_downgrade_next_cycle'.tr()), findsNothing);
  });

  testWidgets('locks purchase actions when purchaseLocked is true even if entitlement is active', (tester) async {
    _setLargeTestSurface(tester);

    final controller = _TestBillingController(
      initialState: BillingState(
        loading: false,
        products: [
          _product(id: 'storage_100gb_monthly', title: 'Pro1', price: '\$0.4'),
          _product(id: 'storage_500gb_monthly', title: 'Pro2', price: '\$5'),
        ],
        entitlement: {
          'productId': 'storage_500gb_monthly',
          'entitlementStatus': 'active',
          'purchaseLocked': true,
          'purchaseLockReason': 'pause_scheduled',
        },
      ),
    );

    await _pumpBillingPage(tester, controller);

    expect(find.text('subscription.purchase_locked_manage_subscription'.tr()), findsOneWidget);
    expect(find.text('billing.select_plan'.tr()), findsNothing);
    expect(find.text('subscription.cta_upgrade_now'.tr()), findsNothing);
    expect(find.text('subscription.cta_downgrade_next_cycle'.tr()), findsNothing);
  });
}

void _setLargeTestSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 3200);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpBillingPage(WidgetTester tester, BillingController controller) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: locales.values.toList(),
      path: translationsPath,
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      assetLoader: const CodegenLoader(),
      saveLocale: false,
      child: ProviderScope(
        overrides: [billingControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(debugShowCheckedModeBanner: false, home: BillingPage()),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

ProductDetails _product({required String id, required String title, required String price}) {
  return ProductDetails(
    id: id,
    title: title,
    description: '$title plan',
    price: price,
    rawPrice: 1,
    currencyCode: 'USD',
    currencySymbol: '\$',
  );
}

class _TestBillingController extends BillingController {
  _TestBillingController({required BillingState initialState})
    : super(
        repo: _FakeBillingRepository(),
        iap: IapService(iap: _FakeInAppPurchase()),
      ) {
    state = initialState;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> refreshUsage({bool includeReferral = true}) async {}

  @override
  Future<void> buy(ProductDetails p, {String? offerToken, String? activeProductId}) async {}

  @override
  Future<void> fakeBuy(String productId) async {}

  @override
  Future<void> restore() async {}
}

class _FakeBillingRepository extends Fake implements BillingRepository {}

class _FakeInAppPurchase extends Fake implements InAppPurchase {}
