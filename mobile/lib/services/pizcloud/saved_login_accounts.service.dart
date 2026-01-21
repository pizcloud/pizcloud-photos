import 'dart:convert';

import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/pizcloud/saved_login_account.model.dart';

class SavedLoginAccountsService {
  static const bool limitSavedAccountsEnabled = true;
  static const int maxSavedAccounts = 5;

  const SavedLoginAccountsService();

  List<SavedLoginAccount> load() {
    final jsonString = Store.tryGet(StoreKey.pizcloudSavedLoginAccounts);
    if (jsonString == null || jsonString.trim().isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final accounts = jsonList
          .map((entry) => SavedLoginAccount.fromJson(entry as Map<String, dynamic>))
          .where((account) => account.email.isNotEmpty)
          .toList();

      accounts.sort((a, b) => b.lastLoginAt.compareTo(a.lastLoginAt));
      return _applyLimit(accounts);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<SavedLoginAccount> accounts) async {
    final trimmed = _applyLimit(accounts);
    final jsonString = jsonEncode(trimmed.map((account) => account.toJson()).toList());
    await Store.put(StoreKey.pizcloudSavedLoginAccounts, jsonString);
  }

  Future<List<SavedLoginAccount>> addOrUpdateFromUser(UserDto user) async {
    final accounts = load();
    final normalizedEmail = user.email.trim().toLowerCase();
    final updated = accounts.where((account) => account.email.toLowerCase() != normalizedEmail).toList();

    updated.insert(0, SavedLoginAccount.fromUser(user, DateTime.now()));
    final sorted = _applyLimit(updated);
    await saveAll(sorted);
    return sorted;
  }

  Future<List<SavedLoginAccount>> removeByEmail(String email) async {
    final accounts = load();
    final normalizedEmail = email.trim().toLowerCase();
    final updated = accounts.where((account) => account.email.toLowerCase() != normalizedEmail).toList();
    await saveAll(updated);
    return updated;
  }

  List<SavedLoginAccount> _applyLimit(List<SavedLoginAccount> accounts) {
    if (!limitSavedAccountsEnabled) {
      return accounts;
    }
    return accounts.take(maxSavedAccounts).toList();
  }
}
