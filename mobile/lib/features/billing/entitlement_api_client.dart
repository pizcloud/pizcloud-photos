import 'dart:convert';
import 'package:http/http.dart' as http;

class EntitlementApiClient {
  EntitlementApiClient({required this.immichBaseUrl, required this.billingBaseUrl, required this.authToken});

  final String immichBaseUrl;
  final String billingBaseUrl;
  final String authToken;

  Map<String, String> _authJson() => {'Authorization': 'Bearer $authToken', 'Content-Type': 'application/json'};

  Future<Map<String, dynamic>?> getEntitlements() async {
    final res = await http.get(
      Uri.parse('$immichBaseUrl/billing/entitlements'),
      headers: {'Authorization': 'Bearer $authToken'},
    );
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    return null;
  }

  Future<Map<String, dynamic>> getUsage() async {
    final res = await http.get(
      Uri.parse('$immichBaseUrl/billing/usage'),
      headers: {'Authorization': 'Bearer $authToken'},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load usage: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> verifyIosReceipt({required String productId, required String receiptBase64}) async {
    final res = await http.post(
      Uri.parse('$billingBaseUrl/v1/iap/ios/verify'),
      headers: _authJson(),
      body: jsonEncode({'productId': productId, 'receiptData': receiptBase64}),
    );
    if (res.statusCode != 200) {
      throw Exception('iOS verify failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> verifyAndroidPurchase({
    required String productId,
    required String purchaseToken,
    required String packageName,
  }) async {
    final res = await http.post(
      Uri.parse('$billingBaseUrl/v1/iap/android/verify'),
      headers: _authJson(),
      body: jsonEncode({'productId': productId, 'purchaseToken': purchaseToken, 'packageName': packageName}),
    );
    if (res.statusCode != 200) {
      throw Exception('Android verify failed: ${res.statusCode} ${res.body}');
    }
  }
}
