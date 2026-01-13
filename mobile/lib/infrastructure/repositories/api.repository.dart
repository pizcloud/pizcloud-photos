import 'package:immich_mobile/constants/errors.dart';
import 'package:immich_mobile/domain/models/store.model.dart'; // pizcloud
import 'package:immich_mobile/entities/store.entity.dart'; // pizcloud
import 'package:immich_mobile/services/api.service.dart'; // pizcloud

class ApiRepository {
  const ApiRepository();
  // pizcloud
  void ensureEndpoint(ApiService apiService) {
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (endpoint == null || endpoint.isEmpty) {
      return;
    }
    if (apiService.apiClient.basePath == endpoint) {
      return;
    }
    apiService.setEndpoint(endpoint);
  }

  Future<T> checkNullWithService<T>(ApiService apiService, Future<T?> Function() action) async {
    ensureEndpoint(apiService);
    return checkNull(action());
  }
  // #pizcloud

  Future<T> checkNull<T>(Future<T?> future) async {
    final response = await future;
    if (response == null) throw const NoResponseDtoError();
    return response;
  }
}
