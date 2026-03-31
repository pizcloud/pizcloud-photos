import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/pizcloud/walkthrough_state.service.dart';

enum FirstLoginWalkthroughStep {
  dateBrowseYear,
  dateBrowseMonth,
  dateBrowseFirstMonthRow,
  backupTab,
  backupSelectButton,
}

extension FirstLoginWalkthroughStepExtension on FirstLoginWalkthroughStep {
  String get messageKey => switch (this) {
    FirstLoginWalkthroughStep.dateBrowseYear => 'walkthrough_first_login_step_year',
    FirstLoginWalkthroughStep.dateBrowseMonth => 'walkthrough_first_login_step_month',
    FirstLoginWalkthroughStep.dateBrowseFirstMonthRow => 'walkthrough_first_login_step_first_month_row',
    FirstLoginWalkthroughStep.backupTab => 'walkthrough_first_login_step_backup_tab',
    FirstLoginWalkthroughStep.backupSelectButton => 'walkthrough_first_login_step_backup_select',
  };

  int get order => switch (this) {
    FirstLoginWalkthroughStep.dateBrowseYear => 1,
    FirstLoginWalkthroughStep.dateBrowseMonth => 2,
    FirstLoginWalkthroughStep.dateBrowseFirstMonthRow => 3,
    FirstLoginWalkthroughStep.backupTab => 4,
    FirstLoginWalkthroughStep.backupSelectButton => 5,
  };
}

class FirstLoginWalkthroughController extends StateNotifier<FirstLoginWalkthroughStep?> {
  FirstLoginWalkthroughController({WalkthroughStateService? remoteStateService})
    : _remoteStateService = remoteStateService ?? walkthroughStateService,
      super(null);

  static const int _firstLoginWalkthroughVersion = 1;
  static const Duration _remoteStateTimeout = Duration(milliseconds: 550);

  final WalkthroughStateService _remoteStateService;

  Future<void> initializeIfNeeded() async {
    if (state != null) {
      return;
    }

    final bool completed = Store.get(StoreKey.firstLoginWalkthroughCompleted, false);
    final bool pending = Store.get(StoreKey.firstLoginWalkthroughPending, false);
    if (completed || !pending) {
      return;
    }

    final bool? remoteCompleted = await _fetchRemoteCompletedState();
    if (remoteCompleted == true) {
      await _applyRemoteCompletedState();
      return;
    }

    if (!mounted) {
      return;
    }
    final bool completedAfterRemote = Store.get(StoreKey.firstLoginWalkthroughCompleted, false);
    final bool pendingAfterRemote = Store.get(StoreKey.firstLoginWalkthroughPending, false);
    if (state != null || completedAfterRemote || !pendingAfterRemote) {
      return;
    }

    state = FirstLoginWalkthroughStep.dateBrowseYear;
  }

  Future<void> markPendingStartIfNeeded() async {
    final bool completed = Store.get(StoreKey.firstLoginWalkthroughCompleted, false);
    if (completed) {
      return;
    }
    await Store.put(StoreKey.firstLoginWalkthroughPending, true);
    // Keep login flow non-blocking; if server already marks this user completed, local state will reconcile.
    unawaited(_syncCompletedFromRemoteIfAny());
  }

  void onDateBrowseYearTapped() {
    _advanceIfCurrent(
      expected: FirstLoginWalkthroughStep.dateBrowseYear,
      next: FirstLoginWalkthroughStep.dateBrowseMonth,
    );
  }

  void onDateBrowseMonthTapped() {
    _advanceIfCurrent(
      expected: FirstLoginWalkthroughStep.dateBrowseMonth,
      next: FirstLoginWalkthroughStep.dateBrowseFirstMonthRow,
    );
  }

  void onDateBrowseFirstMonthRowTapped() {
    _advanceIfCurrent(
      expected: FirstLoginWalkthroughStep.dateBrowseFirstMonthRow,
      next: FirstLoginWalkthroughStep.backupTab,
    );
  }

  void onBackupTabTapped() {
    _advanceIfCurrent(
      expected: FirstLoginWalkthroughStep.backupTab,
      next: FirstLoginWalkthroughStep.backupSelectButton,
    );
  }

  void onBackupSelectTapped() {
    if (state != FirstLoginWalkthroughStep.backupSelectButton) {
      return;
    }

    _finishWalkthrough();
  }

  void onTargetMissingTimeout(FirstLoginWalkthroughStep missingStep) {
    if (state != missingStep) {
      return;
    }

    switch (missingStep) {
      case FirstLoginWalkthroughStep.dateBrowseYear:
      case FirstLoginWalkthroughStep.dateBrowseMonth:
        // Keep current step; these targets should exist in normal flow.
        return;
      case FirstLoginWalkthroughStep.dateBrowseFirstMonthRow:
        state = FirstLoginWalkthroughStep.backupTab;
        return;
      case FirstLoginWalkthroughStep.backupTab:
      case FirstLoginWalkthroughStep.backupSelectButton:
        _finishWalkthrough();
        return;
    }
  }

  void onBackupTabBlockedByReadonly() {
    if (state != FirstLoginWalkthroughStep.backupTab) {
      return;
    }
    _finishWalkthrough();
  }

  void _advanceIfCurrent({required FirstLoginWalkthroughStep expected, required FirstLoginWalkthroughStep next}) {
    if (state != expected) {
      return;
    }
    state = next;
  }

  Future<void> _persistCompletion() async {
    await _setCompletedLocally();
    unawaited(_remoteStateService.markFirstLoginCompleted(version: _firstLoginWalkthroughVersion));
  }

  void _finishWalkthrough() {
    state = null;
    unawaited(_persistCompletion());
  }

  Future<void> _setCompletedLocally() async {
    await Store.put(StoreKey.firstLoginWalkthroughCompleted, true);
    await Store.put(StoreKey.firstLoginWalkthroughPending, false);
  }

  Future<bool?> _fetchRemoteCompletedState() async {
    try {
      final FirstLoginWalkthroughRemoteState? remoteState = await _remoteStateService.fetchFirstLoginState().timeout(
        _remoteStateTimeout,
      );
      if (remoteState == null) {
        return null;
      }
      // Keep version available for future rollout compatibility without changing current flow.
      final int? version = remoteState.version;
      if (version != null && version < 0) {
        return null;
      }
      return remoteState.completed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncCompletedFromRemoteIfAny() async {
    final bool? remoteCompleted = await _fetchRemoteCompletedState();
    if (remoteCompleted == true) {
      await _applyRemoteCompletedState();
    }
  }

  Future<void> _applyRemoteCompletedState() async {
    if (!mounted) {
      return;
    }
    if (state != null) {
      state = null;
    }
    await _setCompletedLocally();
  }
}

final firstLoginWalkthroughControllerProvider =
    StateNotifierProvider<FirstLoginWalkthroughController, FirstLoginWalkthroughStep?>(
      (ref) => FirstLoginWalkthroughController(),
    );
