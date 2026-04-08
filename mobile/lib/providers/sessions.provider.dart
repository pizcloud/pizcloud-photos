import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/repositories/sessions_api.repository.dart';
import 'package:openapi/api.dart';

class DeviceSessionsState {
  const DeviceSessionsState({
    required this.sessions,
    required this.isLoading,
    required this.isRefreshing,
    required this.isLoggingOutAll,
    required this.deletingSessionIds,
    required this.errorMessage,
    required this.hasLoaded,
  });

  const DeviceSessionsState.initial()
    : sessions = const [],
      isLoading = false,
      isRefreshing = false,
      isLoggingOutAll = false,
      deletingSessionIds = const <String>{},
      errorMessage = null,
      hasLoaded = false;

  final List<SessionResponseDto> sessions;
  final bool isLoading;
  final bool isRefreshing;
  final bool isLoggingOutAll;
  final Set<String> deletingSessionIds;
  final String? errorMessage;
  final bool hasLoaded;

  DeviceSessionsState copyWith({
    List<SessionResponseDto>? sessions,
    bool? isLoading,
    bool? isRefreshing,
    bool? isLoggingOutAll,
    Set<String>? deletingSessionIds,
    String? errorMessage,
    bool clearError = false,
    bool? hasLoaded,
  }) {
    return DeviceSessionsState(
      sessions: sessions ?? this.sessions,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoggingOutAll: isLoggingOutAll ?? this.isLoggingOutAll,
      deletingSessionIds: deletingSessionIds != null
          ? Set<String>.unmodifiable(deletingSessionIds)
          : this.deletingSessionIds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

class DeviceSessionsNotifier extends StateNotifier<DeviceSessionsState> {
  DeviceSessionsNotifier(this._sessionsRepository) : super(const DeviceSessionsState.initial()) {
    unawaited(load());
  }

  final SessionsAPIRepository _sessionsRepository;

  Future<void> load({bool force = false}) async {
    if (state.isLoading || state.isRefreshing) {
      return;
    }
    if (!force && state.hasLoaded) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    await _fetchSessions();
  }

  Future<void> refresh() async {
    if (state.isRefreshing || state.isLoading) {
      return;
    }

    state = state.copyWith(isRefreshing: true, clearError: true);
    await _fetchSessions();
  }

  Future<bool> logoutSession(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return false;
    }
    if (state.isLoggingOutAll || state.deletingSessionIds.contains(normalizedSessionId)) {
      return false;
    }

    final deleting = Set<String>.from(state.deletingSessionIds)..add(normalizedSessionId);
    state = state.copyWith(deletingSessionIds: deleting, clearError: true);

    try {
      await _sessionsRepository.deleteSession(normalizedSessionId);
      await refresh();
      return true;
    } catch (error) {
      state = state.copyWith(errorMessage: _mapError(error));
      return false;
    } finally {
      final updatedDeleting = Set<String>.from(state.deletingSessionIds)..remove(normalizedSessionId);
      state = state.copyWith(deletingSessionIds: updatedDeleting);
    }
  }

  Future<bool> logoutAllOtherSessions() async {
    if (state.isLoggingOutAll) {
      return false;
    }

    state = state.copyWith(isLoggingOutAll: true, clearError: true);
    try {
      await _sessionsRepository.deleteAllSessions();
      await refresh();
      return true;
    } catch (error) {
      state = state.copyWith(errorMessage: _mapError(error));
      return false;
    } finally {
      state = state.copyWith(isLoggingOutAll: false);
    }
  }

  Future<void> _fetchSessions() async {
    try {
      final sessions = await _sessionsRepository.getSessions();
      state = state.copyWith(
        sessions: _sortedSessions(sessions),
        isLoading: false,
        isRefreshing: false,
        clearError: true,
        hasLoaded: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, isRefreshing: false, errorMessage: _mapError(error), hasLoaded: true);
    }
  }

  List<SessionResponseDto> _sortedSessions(List<SessionResponseDto> sessions) {
    final sorted = List<SessionResponseDto>.from(sessions);
    sorted.sort((left, right) {
      if (left.current != right.current) {
        return left.current ? -1 : 1;
      }

      final leftDate = DateTime.tryParse(left.updatedAt) ?? DateTime.tryParse(left.createdAt);
      final rightDate = DateTime.tryParse(right.updatedAt) ?? DateTime.tryParse(right.createdAt);

      if (leftDate == null && rightDate == null) {
        return 0;
      }
      if (leftDate == null) {
        return 1;
      }
      if (rightDate == null) {
        return -1;
      }

      return rightDate.compareTo(leftDate);
    });
    return sorted;
  }

  String _mapError(Object error) {
    if (error is ApiException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return 'HTTP ${error.code}';
    }
    return error.toString();
  }
}

final deviceSessionsProvider = StateNotifierProvider.autoDispose<DeviceSessionsNotifier, DeviceSessionsState>((ref) {
  return DeviceSessionsNotifier(ref.watch(sessionsAPIRepositoryProvider));
});
