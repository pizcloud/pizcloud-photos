import 'dart:convert';
import 'package:immich_mobile/domain/models/store.model.dart'; // pizcloud
import 'package:immich_mobile/entities/store.entity.dart'; // pizcloud
import 'package:immich_mobile/services/api.service.dart';
import 'package:openapi/api.dart';

// pizcloud
void _ensureEndpoint(ApiService apiService) {
  final endpoint = Store.tryGet(StoreKey.serverEndpoint);
  if (endpoint == null || endpoint.isEmpty) {
    return;
  }
  if (apiService.apiClient.basePath == endpoint) {
    return;
  }
  // old: no endpoint safeguard before invokeAPI
  // apiService.apiClient.basePath = endpoint;
  apiService.setEndpoint(endpoint);
}
// #pizcloud

({List<String> userIds, List<String> missingEmails}) _emptyResolution() =>
    (userIds: const <String>[], missingEmails: const <String>[]);

Future<({List<String> userIds, List<String> missingEmails})> resolvePartnerUserIdsByEmail({
  required ApiService apiService,
  required Iterable<String> emails,
}) async {
  final normalizedEmails = emails.map((email) => email.trim().toLowerCase()).where((email) => email.isNotEmpty).toSet();

  if (normalizedEmails.isEmpty) {
    return _emptyResolution();
  }

  // final response = await apiService.apiClient.invokeAPI(
  _ensureEndpoint(apiService); // pizcloud
  final response = await apiService.apiClient.invokeAPI(
    '/partners/resolve-emails',
    'POST',
    [],
    {'emails': normalizedEmails.toList()},
    {},
    {},
    'application/json',
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ApiException(response.statusCode, response.body);
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final userIds = (data['userIds'] as List<dynamic>? ?? const []).cast<String>();
  final missingEmails = (data['missingEmails'] as List<dynamic>? ?? const []).cast<String>();

  return (userIds: userIds, missingEmails: missingEmails);
}
