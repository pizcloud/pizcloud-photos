import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'billing_state.dart';
import 'billing_repository.dart';
import 'iap_service.dart';

class BillingController extends StateNotifier<BillingState> {
  BillingController({required this.repo, required this.iap}) : super(BillingState.initial());

  final BillingRepository repo;
  final IapService iap;

  Future<void> init() async {
    try {
      final ok = await iap.isAvailable();
      if (!ok) {
        state = state.copy(loading: false, error: 'In-App Purchases not available');
        return;
      }
      iap.listen((p) async {
        try {
          await repo.handlePurchase(p);
          final ent = await repo.loadEntitlement();
          final usage = await repo.loadUsage();
          state = state.copy(entitlement: ent, usage: usage);
        } catch (e) {
          state = state.copy(error: '$e');
        }
      });

      final resp = await iap.queryProducts();
      final ent = await repo.loadEntitlement();
      final usage = await repo.loadUsage();

      if (resp.error != null) {
        state = state.copy(loading: false, error: resp.error!.message, entitlement: ent, usage: usage);
      } else {
        state = state.copy(loading: false, products: resp.productDetails, entitlement: ent, usage: usage);
      }
    } catch (e) {
      state = state.copy(loading: false, error: '$e');
    }
  }

  Future<void> buy(ProductDetails p) => repo.purchase(p);
  Future<void> refreshUsage() async {
    final usage = await repo.loadUsage();
    state = state.copy(usage: usage);
  }

  Future<void> restore() => iap.restore();

  @override
  void dispose() {
    iap.dispose();
    super.dispose();
  }
}
