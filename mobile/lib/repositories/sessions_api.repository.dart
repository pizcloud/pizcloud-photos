import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/sessions/session_create_response.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:immich_mobile/services/api.service.dart'; // pizcloud
import 'package:openapi/api.dart';

final sessionsAPIRepositoryProvider = Provider(
  (ref) => SessionsAPIRepository(ref.watch(apiServiceProvider)), // pizcloud
);

class SessionsAPIRepository extends ApiRepository {
  // pizcloud
  final ApiService _apiService;
  // final SessionsApi _api;

  SessionsAPIRepository(this._apiService);
  // SessionsAPIRepository(this._api);

  SessionsApi get _api => _apiService.sessionsApi;
  // #pizcloud

  // pizcloud
  Future<List<SessionResponseDto>> getSessions() async {
    ensureEndpoint(_apiService);
    return await _api.getSessions() ?? <SessionResponseDto>[];
  }

  Future<void> deleteSession(String id) async {
    ensureEndpoint(_apiService);
    await _api.deleteSession(id);
  }

  Future<void> deleteAllSessions() async {
    ensureEndpoint(_apiService);
    await _api.deleteAllSessions();
  }
  // #pizcloud

  Future<SessionCreateResponse> createSession(String deviceType, String deviceOS, {int? duration}) async {
    // pizcloud
    // final dto = await checkNull(
    //   _api.createSession(SessionCreateDto(deviceType: deviceType, deviceOS: deviceOS, duration: duration)),
    // );
    final dto = await checkNullWithService(
      _apiService,
      () => _api.createSession(SessionCreateDto(deviceType: deviceType, deviceOS: deviceOS, duration: duration)),
    );
    // #pizcloud

    return SessionCreateResponse(
      id: dto.id,
      current: dto.current,
      deviceType: deviceType,
      deviceOS: deviceOS,
      expiresAt: dto.expiresAt,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
      token: dto.token,
    );
  }
}
