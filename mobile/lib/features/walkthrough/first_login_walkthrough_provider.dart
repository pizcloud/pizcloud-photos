import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

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
  FirstLoginWalkthroughController() : super(null);

  Future<void> initializeIfNeeded() async {
    if (state != null) {
      return;
    }

    final bool completed = Store.get(StoreKey.firstLoginWalkthroughCompleted, false);
    final bool pending = Store.get(StoreKey.firstLoginWalkthroughPending, false);
    if (completed || !pending) {
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

    state = null;
    unawaited(_persistCompletion());
  }

  void _advanceIfCurrent({required FirstLoginWalkthroughStep expected, required FirstLoginWalkthroughStep next}) {
    if (state != expected) {
      return;
    }
    state = next;
  }

  Future<void> _persistCompletion() async {
    await Store.put(StoreKey.firstLoginWalkthroughCompleted, true);
    await Store.put(StoreKey.firstLoginWalkthroughPending, false);
  }
}

final firstLoginWalkthroughControllerProvider =
    StateNotifierProvider<FirstLoginWalkthroughController, FirstLoginWalkthroughStep?>(
      (ref) => FirstLoginWalkthroughController(),
    );
