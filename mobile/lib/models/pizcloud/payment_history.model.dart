class PaymentHistoryPagination {
  const PaymentHistoryPagination({required this.page, required this.limit, required this.total});

  final int page;
  final int limit;
  final int total;

  factory PaymentHistoryPagination.fromJson(
    Map<String, dynamic> json, {
    int fallbackPage = 1,
    int fallbackLimit = 20,
    int fallbackTotal = 0,
  }) {
    final page = _asPositiveInt(json['page']) ?? fallbackPage;
    final limit = _asPositiveInt(json['limit']) ?? fallbackLimit;
    final total = _asNonNegativeInt(json['total']) ?? fallbackTotal;

    return PaymentHistoryPagination(page: page, limit: limit, total: total);
  }

  const PaymentHistoryPagination.empty() : page = 1, limit = 20, total = 0;

  bool get hasMore => page * limit < total;
}

class PaymentHistoryItem {
  const PaymentHistoryItem({
    required this.id,
    this.productId,
    this.planCode,
    this.planSizeGb,
    this.billingPeriod,
    required this.renewalNumber,
    required this.kind,
    required this.amount,
    required this.finalAmount,
    required this.discountAmount,
    required this.currency,
    required this.status,
    this.platform,
    this.providerTransactionId,
    this.periodEndAt,
    this.createdAt,
  });

  final String id;
  final String? productId;
  final String? planCode;
  final int? planSizeGb;
  final String? billingPeriod;
  final int renewalNumber;
  final String kind;
  final double amount;
  final double finalAmount;
  final double discountAmount;
  final String currency;
  final String status;
  final String? platform;
  final String? providerTransactionId;
  final DateTime? periodEndAt;
  final DateTime? createdAt;

  factory PaymentHistoryItem.fromJson(Map<String, dynamic> json) {
    return PaymentHistoryItem(
      id: _asString(json['id']) ?? '',
      productId: _asNullableString(json['productId']),
      planCode: _asNullableString(json['planCode']),
      planSizeGb: _asNullableInt(json['planSizeGb']),
      billingPeriod: _asNullableString(json['billingPeriod'])?.toLowerCase(),
      renewalNumber: _asNonNegativeInt(json['renewalNumber']) ?? 0,
      kind: _asString(json['kind'])?.toLowerCase() ?? '',
      amount: _asDouble(json['amount']) ?? 0,
      finalAmount: _asDouble(json['finalAmount']) ?? 0,
      discountAmount: _asDouble(json['discountAmount']) ?? 0,
      currency: _asString(json['currency'])?.toUpperCase() ?? 'USD',
      status: _asString(json['status'])?.toLowerCase() ?? 'paid',
      platform: _asNullableString(json['platform'])?.toLowerCase(),
      providerTransactionId: _asNullableString(json['providerTransactionId']),
      periodEndAt: _asNullableDateTime(json['periodEndAt']),
      createdAt: _asNullableDateTime(json['createdAt']),
    );
  }
}

class PaymentHistoryListResponse {
  const PaymentHistoryListResponse({required this.pagination, required this.items});

  final PaymentHistoryPagination pagination;
  final List<PaymentHistoryItem> items;

  factory PaymentHistoryListResponse.empty() {
    return const PaymentHistoryListResponse(
      pagination: PaymentHistoryPagination.empty(),
      items: <PaymentHistoryItem>[],
    );
  }
}

int? _asPositiveInt(dynamic value) {
  if (value is num) {
    final intValue = value.toInt();
    return intValue > 0 ? intValue : null;
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }
  return null;
}

int? _asNonNegativeInt(dynamic value) {
  if (value is num) {
    final intValue = value.toInt();
    return intValue >= 0 ? intValue : null;
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
  }
  return null;
}

int? _asNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value.trim());
  }

  return null;
}

double? _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value.trim());
  }

  return null;
}

String? _asString(dynamic value) {
  if (value == null) {
    return null;
  }

  final normalized = value.toString().trim();
  if (normalized.isEmpty) {
    return null;
  }

  return normalized;
}

String? _asNullableString(dynamic value) => _asString(value);

DateTime? _asNullableDateTime(dynamic value) {
  final raw = _asString(value);
  if (raw == null) {
    return null;
  }

  try {
    return DateTime.parse(raw);
  } catch (_) {
    return null;
  }
}
