import 'package:in_app_purchase/in_app_purchase.dart';

class BillingState {
  final bool loading;
  final List<ProductDetails> products;
  final Map<String, dynamic>? entitlement;
  final Map<String, dynamic>? usage;
  final String? error;

  BillingState({required this.loading, required this.products, this.entitlement, this.usage, this.error});

  factory BillingState.initial() => BillingState(loading: true, products: const []);

  BillingState copy({
    bool? loading,
    List<ProductDetails>? products,
    Map<String, dynamic>? entitlement,
    Map<String, dynamic>? usage,
    String? error,
  }) => BillingState(
    loading: loading ?? this.loading,
    products: products ?? this.products,
    entitlement: entitlement ?? this.entitlement,
    usage: usage ?? this.usage,
    error: error,
  );
}
