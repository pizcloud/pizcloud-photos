import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/infrastructure/repositories/api.repository.dart';
import 'package:immich_mobile/infrastructure/utils/user.converter.dart';
import 'package:immich_mobile/services/api.service.dart'; // pizcloud
import 'package:openapi/api.dart';

class UserApiRepository extends ApiRepository {
  // pizcloud
  final ApiService _apiService;
  const UserApiRepository(this._apiService);
  // final UsersApi _api;
  // const UserApiRepository(this._api);
  // #pizcloud

  UsersApi get _api => _apiService.usersApi;

  Future<UserDto?> getMyUser() async {
    // final (adminDto, preferenceDto) = await (_api.getMyUser(), _api.getMyPreferences()).wait; // pizcloud
    ensureEndpoint(_apiService); // pizcloud
    final (adminDto, preferenceDto) = await (_api.getMyUser(), _api.getMyPreferences()).wait;
    if (adminDto == null) return null;

    return UserConverter.fromAdminDto(adminDto, preferenceDto);
  }

  Future<String> createProfileImage({required String name, required Uint8List data}) async {
    // pizcloud
    // final res = await checkNull(_api.createProfileImage(MultipartFile.fromBytes('file', data, filename: name)));
    final res = await checkNullWithService(
      _apiService,
      () => _api.createProfileImage(MultipartFile.fromBytes('file', data, filename: name)),
    );
    // #pizcloud
    return res.profileImagePath;
  }

  Future<List<UserDto>> getAll() async {
    // final dto = await checkNull(_api.searchUsers()); // pizcloud
    final dto = await checkNullWithService(_apiService, () => _api.searchUsers()); // pizcloud
    return dto.map(UserConverter.fromSimpleUserDto).toList();
  }
}
