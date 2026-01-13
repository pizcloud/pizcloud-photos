import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/infrastructure/utils/user.converter.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:immich_mobile/services/api.service.dart'; // pizcloud
import 'package:openapi/api.dart';

enum Direction { sharedWithMe, sharedByMe }

final partnerApiRepositoryProvider = Provider((ref) => PartnerApiRepository(ref.watch(apiServiceProvider))); // pizcloud
// final partnerApiRepositoryProvider = Provider((ref) => PartnerApiRepository(ref.watch(apiServiceProvider).partnersApi)); // pizcloud

class PartnerApiRepository extends ApiRepository {
  // pizcloud
  final ApiService _apiService;
  // old: held a snapshot of PartnersApi
  // final PartnersApi _api;

  PartnerApiRepository(this._apiService);
  // PartnerApiRepository(this._api);

  PartnersApi get _api => _apiService.partnersApi;
  // #pizcloud

  Future<List<UserDto>> getAll(Direction direction) async {
    // pizcloud
    // final response = await checkNull(
    //   _api.getPartners(direction == Direction.sharedByMe ? PartnerDirection.by : PartnerDirection.with_),
    // );
    final response = await checkNullWithService(
      _apiService,
      () => _api.getPartners(direction == Direction.sharedByMe ? PartnerDirection.by : PartnerDirection.with_),
    );
    // #pizcloud
    return response.map(UserConverter.fromPartnerDto).toList();
  }

  Future<UserDto> create(String id) async {
    // final dto = await checkNull(_api.createPartnerDeprecated(id));
    final dto = await checkNullWithService(_apiService, () => _api.createPartnerDeprecated(id)); // pizcloud
    return UserConverter.fromPartnerDto(dto);
  }

  Future<void> delete(String id) {
    // pizcloud
    // return _api.removePartner(id);
    ensureEndpoint(_apiService);
    return _api.removePartner(id);
    // #pizcloud
  }

  Future<UserDto> update(String id, {required bool inTimeline}) async {
    // pizcloud
    // final dto = await checkNull(_api.updatePartner(id, PartnerUpdateDto(inTimeline: inTimeline)));
    final dto = await checkNullWithService(
      _apiService,
      () => _api.updatePartner(id, PartnerUpdateDto(inTimeline: inTimeline)),
    );
    // #pizcloud
    return UserConverter.fromPartnerDto(dto);
  }
}
