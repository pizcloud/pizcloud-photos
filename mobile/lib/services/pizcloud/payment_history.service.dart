import 'package:immich_mobile/models/pizcloud/payment_history.model.dart';
import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class PaymentHistoryApiException implements Exception {
  PaymentHistoryApiException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode;
    if (code == null) {
      return 'PaymentHistoryApiException: $message';
    }
    return 'PaymentHistoryApiException($code): $message';
  }
}

class PaymentHistoryService {
  PaymentHistoryService({PizcloudBaseUrlService? baseUrlService})
    : _baseUrlService = baseUrlService ?? PizcloudBaseUrlService();

  final PizcloudBaseUrlService _baseUrlService;

  late final Future<piz_persist.ApiPersistCookieJarService> _pizApiService = _initPizApiService();

  static const Set<String> _allowedStatus = <String>{'paid', 'failed', 'refunded', 'pending', 'all'};
  static const Set<String> _allowedPlatform = <String>{'android', 'ios', 'all'};

  Future<piz_persist.ApiPersistCookieJarService> _initPizApiService() async {
    final baseUrl = await _baseUrlService.resolveBaseUrl();
    return piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  Future<PaymentHistoryListResponse> fetchPaymentHistory({
    int page = 1,
    int limit = 20,
    String status = 'paid',
    String platform = 'all',
    String? productId,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit.clamp(1, 100).toInt();
    final safeStatus = _normalizeStatus(status);
    final safePlatform = _normalizePlatform(platform);
    final safeProductId = productId?.trim();

    final api = await _pizApiService;
    final response = await api.client.get<dynamic>(
      '/billing/payments',
      queryParameters: <String, dynamic>{
        'page': safePage,
        'limit': safeLimit,
        'status': safeStatus,
        'platform': safePlatform,
        if (safeProductId != null && safeProductId.isNotEmpty) 'productId': safeProductId,
      },
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw PaymentHistoryApiException(
        message: _extractMessage(response.data) ?? 'Failed to load payment history',
        statusCode: statusCode,
      );
    }

    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw PaymentHistoryApiException(message: 'Invalid payment history payload');
    }

    final paginationRaw = body['pagination'];
    final paginationMap = paginationRaw is Map<String, dynamic> ? paginationRaw : const <String, dynamic>{};
    final pagination = PaymentHistoryPagination.fromJson(
      paginationMap,
      fallbackPage: safePage,
      fallbackLimit: safeLimit,
      fallbackTotal: 0,
    );

    final itemsRaw = body['items'];
    final items = <PaymentHistoryItem>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map<String, dynamic>) {
          items.add(PaymentHistoryItem.fromJson(item));
        }
      }
    }

    return PaymentHistoryListResponse(pagination: pagination, items: items);
  }

  String _normalizeStatus(String value) {
    final normalized = value.trim().toLowerCase();
    if (_allowedStatus.contains(normalized)) {
      return normalized;
    }
    return 'paid';
  }

  String _normalizePlatform(String value) {
    final normalized = value.trim().toLowerCase();
    if (_allowedPlatform.contains(normalized)) {
      return normalized;
    }
    return 'all';
  }

  String? _extractMessage(dynamic body) {
    if (body is! Map<String, dynamic>) {
      return null;
    }

    final message = body['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }

    if (message is List && message.isNotEmpty) {
      final first = message.first;
      if (first is String && first.isNotEmpty) {
        return first;
      }
    }

    return null;
  }
}

final paymentHistoryService = PaymentHistoryService();
