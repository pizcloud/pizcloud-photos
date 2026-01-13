import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:immich_mobile/services/api.service.dart'; // pizcloud
import 'package:openapi/api.dart';

final personApiRepositoryProvider = Provider((ref) => PersonApiRepository(ref.watch(apiServiceProvider))); // pizcloud
// final personApiRepositoryProvider = Provider((ref) => PersonApiRepository(ref.watch(apiServiceProvider).peopleApi)); // pizcloud

class PersonApiRepository extends ApiRepository {
  // pizcloud
  final ApiService _apiService;
  // old: held a snapshot of PeopleApi
  // final PeopleApi _api;

  PersonApiRepository(this._apiService);
  // PersonApiRepository(this._api);

  PeopleApi get _api => _apiService.peopleApi;
  // #pizcloud

  Future<List<PersonDto>> getAll() async {
    // final dto = await checkNull(_api.getAllPeople());
    final dto = await checkNullWithService(_apiService, () => _api.getAllPeople()); // pizcloud
    return dto.people.map(_toPerson).toList();
  }

  Future<PersonDto> update(String id, {String? name, DateTime? birthday}) async {
    // pizcloud
    // final dto = await checkNull(_api.updatePerson(id, PersonUpdateDto(name: name, birthDate: birthday)));
    final dto = await checkNullWithService(
      _apiService,
      () => _api.updatePerson(id, PersonUpdateDto(name: name, birthDate: birthday)),
    );
    // #pizcloud
    return _toPerson(dto);
  }

  static PersonDto _toPerson(PersonResponseDto dto) => PersonDto(
    birthDate: dto.birthDate,
    id: dto.id,
    isHidden: dto.isHidden,
    name: dto.name,
    thumbnailPath: dto.thumbnailPath,
  );
}
