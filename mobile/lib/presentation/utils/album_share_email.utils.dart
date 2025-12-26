import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';

({List<String> userIds, List<String> missingEmails}) _emptyResolution() =>
    (userIds: const <String>[], missingEmails: const <String>[]);

Future<({List<String> userIds, List<String> missingEmails})> resolveShareUserIdsByEmail({
  required Drift drift,
  required Iterable<String> emails,
}) async {
  final normalizedEmails = emails
      .map((email) => email.trim().toLowerCase())
      .where((email) => email.isNotEmpty)
      .toSet();

  if (normalizedEmails.isEmpty) {
    return _emptyResolution();
  }

  final rows = await (drift.select(drift.userEntity)..where((row) => row.email.isIn(normalizedEmails))).get();

  final idByEmail = <String, String>{
    for (final row in rows) row.email.toLowerCase(): row.id,
  };

  final userIds = <String>[];
  final missingEmails = <String>[];

  for (final email in normalizedEmails) {
    final userId = idByEmail[email];
    if (userId == null) {
      missingEmails.add(email);
    } else {
      userIds.add(userId);
    }
  }

  return (userIds: userIds, missingEmails: missingEmails);
}
