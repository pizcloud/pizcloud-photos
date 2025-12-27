// import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'dart:convert';
import 'package:immich_mobile/services/api.service.dart';
import 'package:openapi/api.dart';

({List<String> userIds, List<String> missingEmails}) _emptyResolution() =>
    (userIds: const <String>[], missingEmails: const <String>[]);

// Future<({List<String> userIds, List<String> missingEmails})> resolveShareUserIdsByEmail({
//   required Drift drift,
//   required Iterable<String> emails,
// }) async {
//   final normalizedEmails = emails
//       .map((email) => email.trim().toLowerCase())
//       .where((email) => email.isNotEmpty)
//       .toSet();
//   if (normalizedEmails.isEmpty) {
//     return _emptyResolution();
//   }
//   final rows = await (drift.select(drift.userEntity)..where((row) => row.email.isIn(normalizedEmails))).get();
//   final idByEmail = <String, String>{
//     for (final row in rows) row.email.toLowerCase(): row.id,
//   };
//   final userIds = <String>[];
//   final missingEmails = <String>[];
//   for (final email in normalizedEmails) {
//     final userId = idByEmail[email];
//     if (userId == null) {
//       missingEmails.add(email);
//     } else {
//       userIds.add(userId);
//     }
//   }
//   return (userIds: userIds, missingEmails: missingEmails);
// }

Future<({List<String> userIds, List<String> missingEmails})> resolveShareUserIdsByEmail({
  required ApiService apiService,
  required String albumId,
  required Iterable<String> emails,
}) async {
  final normalizedEmails = emails.map((email) => email.trim().toLowerCase()).where((email) => email.isNotEmpty).toSet();

  if (normalizedEmails.isEmpty) {
    return _emptyResolution();
  }

  final response = await apiService.apiClient.invokeAPI(
    '/albums/$albumId/resolve-emails',
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
