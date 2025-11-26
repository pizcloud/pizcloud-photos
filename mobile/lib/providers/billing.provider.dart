import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/domain/models/store.model.dart';

import 'package:immich_mobile/features/billing/entitlement_api_client.dart';
import 'package:immich_mobile/features/billing/iap_service.dart';
import 'package:immich_mobile/features/billing/billing_repository.dart';
import 'package:immich_mobile/features/billing/billing_controller.dart';

/// Separate configuration for the billing-service and Android package name
class BillingConfig {
  const BillingConfig({required this.androidPackageName});

  // final String billingBaseUrl;
  final String androidPackageName;
}

final billingConfigProvider = Provider<BillingConfig>((ref) {
  return const BillingConfig(
    // billingBaseUrl: 'https://anhuynh-venus-series.tail015c11.ts.net:9443', // Ex: https://<url>
    androidPackageName: '', // Ex: com.<brand>.<proj>
  );
});

final iapServiceProvider = Provider<IapService>((ref) => IapService());

final entitlementApiClientProvider = Provider<EntitlementApiClient>((ref) {
  final immichBaseUrl = Store.get(StoreKey.serverEndpoint);
  // final cfg = ref.watch(billingConfigProvider);

  return EntitlementApiClient(immichBaseUrl: immichBaseUrl);
});

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  final api = ref.watch(entitlementApiClientProvider);
  final iap = ref.watch(iapServiceProvider);
  final cfg = ref.watch(billingConfigProvider);
  return BillingRepository(api: api, iap: iap, packageName: cfg.androidPackageName);
});

final billingControllerProvider = StateNotifierProvider<BillingController, dynamic>((ref) {
  final ctl = BillingController(repo: ref.watch(billingRepositoryProvider), iap: ref.watch(iapServiceProvider));
  ctl.init();
  return ctl;
});
