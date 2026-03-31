import 'package:immich_mobile/services/pizcloud/api_persist_cookie_jar.service.dart' as piz_persist;
import 'package:immich_mobile/services/pizcloud/pizcloud_base_url.service.dart';

class FirstLoginWalkthroughRemoteState {
  const FirstLoginWalkthroughRemoteState({required this.completed, this.version});

  final bool completed;
  final int? version;
}

class WalkthroughStateService {
  WalkthroughStateService();

  final PizcloudBaseUrlService _baseUrlService = PizcloudBaseUrlService();
  late final Future<piz_persist.ApiPersistCookieJarService> _pizApiService = _initPizApiService();

  static const String _firstLoginPath = '/walkthrough/first-login';

  Future<piz_persist.ApiPersistCookieJarService> _initPizApiService() async {
    final String baseUrl = await _baseUrlService.resolveBaseUrl();
    return piz_persist.ApiPersistCookieJarService.instance(baseUrl: baseUrl);
  }

  Future<FirstLoginWalkthroughRemoteState?> fetchFirstLoginState() async {
    try {
      final api = await _pizApiService;
      final res = await api.client.get<dynamic>(_firstLoginPath);
      final int status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        return null;
      }

      final Map<String, dynamic>? payload = _extractPayloadMap(res.data);
      if (payload == null) {
        return null;
      }

      final bool? completed = _readBool(payload['completed']) ?? _readBool(payload['isCompleted']);
      if (completed == null) {
        return null;
      }

      final int? version = _readInt(payload['version']);
      return FirstLoginWalkthroughRemoteState(completed: completed, version: version);
    } catch (_) {
      return null;
    }
  }

  Future<bool> markFirstLoginCompleted({required int version}) async {
    try {
      final api = await _pizApiService;
      final res = await api.client.put<dynamic>(
        _firstLoginPath,
        data: <String, dynamic>{'completed': true, 'version': version},
      );
      final int status = res.statusCode ?? 0;
      return status >= 200 && status < 300;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic>? _extractPayloadMap(dynamic data) {
    final Map<String, dynamic>? map = _toMap(data);
    if (map == null) {
      return null;
    }
    final Map<String, dynamic>? wrapped = _toMap(map['data']);
    return wrapped ?? map;
  }

  Map<String, dynamic>? _toMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      try {
        return Map<String, dynamic>.from(data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool? _readBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

final walkthroughStateService = WalkthroughStateService();
