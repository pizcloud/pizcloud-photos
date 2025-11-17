import 'dart:convert';
import 'package:http/http.dart' as http;

class UsageApiClient {
  UsageApiClient({required this.immichBaseUrl, required this.authToken});

  final String immichBaseUrl;
  final String authToken;

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
}
