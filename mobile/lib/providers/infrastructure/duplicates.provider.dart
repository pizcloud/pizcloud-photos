import 'dart:async';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/services/duplicates.service.dart';
import 'package:immich_mobile/infrastructure/repositories/duplicates_api.repository.dart';
import 'package:immich_mobile/providers/api.provider.dart';

final duplicatesApiRepositoryProvider = Provider<DuplicatesApiRepository>(
  (ref) => DuplicatesApiRepository(ref.watch(apiServiceProvider)),
);

final duplicatesServiceProvider = Provider<DuplicatesService>(
  (ref) => DuplicatesService(ref.watch(duplicatesApiRepositoryProvider)),
);

final duplicatesProvider = StateNotifierProvider.autoDispose<DuplicatesNotifier, DuplicatesState>(
  (ref) => DuplicatesNotifier(ref.watch(duplicatesServiceProvider)),
);

class DuplicatesState {
  final AsyncValue<List<DuplicateGroup>> groups;
  final Map<String, Set<String>> keepSelectionByGroupId;
  final Set<String> resolvingGroupIds;
  final Set<String> stackingGroupIds;
  final bool isKeepingAll;
  final bool isDeduplicatingAll;
  final int initialGroupCount;

  const DuplicatesState({
    required this.groups,
    this.keepSelectionByGroupId = const {},
    this.resolvingGroupIds = const {},
    this.stackingGroupIds = const {},
    this.isKeepingAll = false,
    this.isDeduplicatingAll = false,
    this.initialGroupCount = 0,
  });

  const DuplicatesState.initial() : this(groups: const AsyncValue.loading());

  bool get isBulkMutating => isKeepingAll || isDeduplicatingAll;
  bool get isMutating => isBulkMutating || resolvingGroupIds.isNotEmpty || stackingGroupIds.isNotEmpty;

  DuplicatesState copyWith({
    AsyncValue<List<DuplicateGroup>>? groups,
    Map<String, Set<String>>? keepSelectionByGroupId,
    Set<String>? resolvingGroupIds,
    Set<String>? stackingGroupIds,
    bool? isKeepingAll,
    bool? isDeduplicatingAll,
    int? initialGroupCount,
  }) {
    return DuplicatesState(
      groups: groups ?? this.groups,
      keepSelectionByGroupId: keepSelectionByGroupId ?? this.keepSelectionByGroupId,
      resolvingGroupIds: resolvingGroupIds ?? this.resolvingGroupIds,
      stackingGroupIds: stackingGroupIds ?? this.stackingGroupIds,
      isKeepingAll: isKeepingAll ?? this.isKeepingAll,
      isDeduplicatingAll: isDeduplicatingAll ?? this.isDeduplicatingAll,
      initialGroupCount: initialGroupCount ?? this.initialGroupCount,
    );
  }
}

class DuplicatesNotifier extends StateNotifier<DuplicatesState> {
  final DuplicatesService _service;

  DuplicatesNotifier(this._service) : super(const DuplicatesState.initial()) {
    unawaited(load());
  }

  Future<void> load() async {
    state = state.copyWith(groups: const AsyncValue.loading());

    try {
      final groups = await _service.getDuplicateGroups();
      state = state.copyWith(
        groups: AsyncValue.data(groups),
        keepSelectionByGroupId: _getDefaultKeepSelection(groups),
        resolvingGroupIds: const {},
        stackingGroupIds: const {},
        isKeepingAll: false,
        isDeduplicatingAll: false,
        initialGroupCount: groups.length,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(groups: AsyncValue.error(error, stackTrace));
    }
  }

  void setKeepSelection(String duplicateId, String assetId) {
    if (state.isBulkMutating ||
        state.resolvingGroupIds.contains(duplicateId) ||
        state.stackingGroupIds.contains(duplicateId)) {
      return;
    }

    final nextSelectedIds = Set<String>.from(state.keepSelectionByGroupId[duplicateId] ?? const <String>{});
    if (nextSelectedIds.contains(assetId)) {
      nextSelectedIds.remove(assetId);
    } else {
      nextSelectedIds.add(assetId);
    }

    state = state.copyWith(keepSelectionByGroupId: {...state.keepSelectionByGroupId, duplicateId: nextSelectedIds});
  }

  void selectKeepAll(String duplicateId) {
    final groups = state.groups.valueOrNull;
    if (groups == null ||
        state.isBulkMutating ||
        state.resolvingGroupIds.contains(duplicateId) ||
        state.stackingGroupIds.contains(duplicateId)) {
      return;
    }

    final group = groups.firstWhereOrNull((item) => item.duplicateId == duplicateId);
    if (group == null) {
      return;
    }

    state = state.copyWith(
      keepSelectionByGroupId: {
        ...state.keepSelectionByGroupId,
        duplicateId: group.assets.map((item) => item.asset.id).toSet(),
      },
    );
  }

  void selectTrashAll(String duplicateId) {
    if (state.isBulkMutating ||
        state.resolvingGroupIds.contains(duplicateId) ||
        state.stackingGroupIds.contains(duplicateId)) {
      return;
    }

    state = state.copyWith(keepSelectionByGroupId: {...state.keepSelectionByGroupId, duplicateId: <String>{}});
  }

  Future<void> resolveGroup(String duplicateId, {required bool useTrash}) async {
    final groups = state.groups.valueOrNull;
    if (groups == null ||
        state.isBulkMutating ||
        state.resolvingGroupIds.contains(duplicateId) ||
        state.stackingGroupIds.contains(duplicateId)) {
      return;
    }

    final group = groups.firstWhereOrNull((item) => item.duplicateId == duplicateId);
    if (group == null) {
      return;
    }

    final keepAssetIds = Set<String>.from(state.keepSelectionByGroupId[duplicateId] ?? const <String>{});
    if (keepAssetIds.isEmpty && group.assets.length == 1) {
      keepAssetIds.add(group.assets.first.asset.id);
    }

    state = state.copyWith(resolvingGroupIds: {...state.resolvingGroupIds, duplicateId});

    try {
      await _service.resolveGroup(group: group, keepAssetIds: keepAssetIds, useTrash: useTrash);
      _removeGroupFromState(duplicateId);
    } finally {
      final nextResolving = Set<String>.from(state.resolvingGroupIds)..remove(duplicateId);
      state = state.copyWith(resolvingGroupIds: nextResolving);
    }
  }

  Future<void> keepAll() async {
    final groups = state.groups.valueOrNull;
    if (groups == null ||
        groups.isEmpty ||
        state.isBulkMutating ||
        state.resolvingGroupIds.isNotEmpty ||
        state.stackingGroupIds.isNotEmpty) {
      return;
    }

    state = state.copyWith(isKeepingAll: true);
    try {
      await _service.keepAll(groups.map((group) => group.duplicateId).toList(growable: false));
      state = state.copyWith(groups: const AsyncValue.data([]), keepSelectionByGroupId: const {});
    } finally {
      state = state.copyWith(isKeepingAll: false);
    }
  }

  Future<void> stackGroup(String duplicateId) async {
    final groups = state.groups.valueOrNull;
    if (groups == null ||
        state.isBulkMutating ||
        state.resolvingGroupIds.contains(duplicateId) ||
        state.stackingGroupIds.contains(duplicateId)) {
      return;
    }

    final group = groups.firstWhereOrNull((item) => item.duplicateId == duplicateId);
    if (group == null) {
      return;
    }

    state = state.copyWith(stackingGroupIds: {...state.stackingGroupIds, duplicateId});
    try {
      await _service.stackGroup(group);
      _removeGroupFromState(duplicateId);
    } finally {
      final nextStacking = Set<String>.from(state.stackingGroupIds)..remove(duplicateId);
      state = state.copyWith(stackingGroupIds: nextStacking);
    }
  }

  Future<void> deduplicateAll({required bool useTrash}) async {
    final groups = state.groups.valueOrNull;
    if (groups == null ||
        groups.isEmpty ||
        state.isBulkMutating ||
        state.resolvingGroupIds.isNotEmpty ||
        state.stackingGroupIds.isNotEmpty) {
      return;
    }

    final keepSelectionByGroupId = _cloneKeepSelectionMap(state.keepSelectionByGroupId);

    state = state.copyWith(isDeduplicatingAll: true);
    try {
      await _service.deduplicateAll(groups: groups, keepSelectionByGroupId: keepSelectionByGroupId, useTrash: useTrash);
      state = state.copyWith(groups: const AsyncValue.data([]), keepSelectionByGroupId: const {});
    } finally {
      state = state.copyWith(isDeduplicatingAll: false);
    }
  }

  Map<String, Set<String>> _getDefaultKeepSelection(List<DuplicateGroup> groups) {
    return {
      for (final group in groups) group.duplicateId: {_service.suggestKeepAssetId(group)},
    };
  }

  void _removeGroupFromState(String duplicateId) {
    final latestGroups = state.groups.valueOrNull ?? const <DuplicateGroup>[];
    final remainingGroups = latestGroups.where((item) => item.duplicateId != duplicateId).toList(growable: false);
    final keepSelectionByGroupId = _cloneKeepSelectionMap(state.keepSelectionByGroupId)..remove(duplicateId);

    state = state.copyWith(groups: AsyncValue.data(remainingGroups), keepSelectionByGroupId: keepSelectionByGroupId);
  }

  Map<String, Set<String>> _cloneKeepSelectionMap(Map<String, Set<String>> source) {
    return {for (final entry in source.entries) entry.key: Set<String>.from(entry.value)};
  }
}
