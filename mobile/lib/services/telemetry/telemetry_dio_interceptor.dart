import 'package:dio/dio.dart';
import 'package:immich_mobile/services/telemetry/client_telemetry.service.dart';

class ClientTelemetryDioInterceptor extends Interceptor {
  ClientTelemetryDioInterceptor({ClientTelemetryService? telemetry})
    : _telemetry = telemetry ?? ClientTelemetryService.I;

  static const String _startedAtExtraKey = '__clientTelemetry.startedAtMs';
  static const String _metaExtraKey = '__clientTelemetry.meta';
  static const String _eventNameExtraKey = 'clientEventName';

  final ClientTelemetryService _telemetry;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    options.extra[_startedAtExtraKey] = DateTime.now().millisecondsSinceEpoch;
    ClientTelemetryMeta? meta;

    try {
      final headers = Map<String, dynamic>.from(options.headers);
      final eventName = _readEventName(options.extra);
      meta = await _telemetry.attachHeadersToMap(headers, eventName: eventName);
      options.headers
        ..clear()
        ..addAll(headers);

      if (meta != null) {
        options.extra[_metaExtraKey] = meta.toMap();
      }

      _telemetry.logHttpRequest(
        transport: 'dio',
        method: options.method,
        uri: options.uri,
        meta: meta,
        eventName: eventName,
      );
    } catch (_) {
      // fail-open
    }

    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    try {
      final options = response.requestOptions;
      final eventName = _readEventName(options.extra);
      _telemetry.logHttpResponse(
        transport: 'dio',
        method: options.method,
        uri: options.uri,
        status: response.statusCode ?? 0,
        durationMs: _durationMs(options.extra),
        meta: _readMeta(options.extra),
        eventName: eventName,
      );
    } catch (_) {
      // fail-open
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      final options = err.requestOptions;
      final eventName = _readEventName(options.extra);
      _telemetry.logHttpError(
        transport: 'dio',
        method: options.method,
        uri: options.uri,
        error: err.error ?? err.message ?? err.type.name,
        durationMs: _durationMs(options.extra),
        meta: _readMeta(options.extra),
        eventName: eventName,
      );
    } catch (_) {
      // fail-open
    }

    handler.next(err);
  }

  int _durationMs(Map<String, dynamic> extra) {
    final startedAt = extra[_startedAtExtraKey];
    if (startedAt is! int) {
      return 0;
    }

    final duration = DateTime.now().millisecondsSinceEpoch - startedAt;
    return duration < 0 ? 0 : duration;
  }

  String? _readEventName(Map<String, dynamic> extra) {
    final raw = extra[_eventNameExtraKey];
    if (raw is! String) {
      return null;
    }

    final normalized = raw.trim();
    return normalized.isEmpty ? null : normalized;
  }

  ClientTelemetryMeta? _readMeta(Map<String, dynamic> extra) {
    final raw = extra[_metaExtraKey];
    if (raw is! Map) {
      return null;
    }

    final requestId = (raw['requestId'] as String?)?.trim() ?? '';
    final correlationId = (raw['correlationId'] as String?)?.trim() ?? '';
    final clientEventId = (raw['clientEventId'] as String?)?.trim() ?? '';
    final clientSessionId = (raw['clientSessionId'] as String?)?.trim() ?? '';

    if (requestId.isEmpty || correlationId.isEmpty || clientEventId.isEmpty || clientSessionId.isEmpty) {
      return null;
    }

    return ClientTelemetryMeta(
      requestId: requestId,
      correlationId: correlationId,
      clientEventId: clientEventId,
      clientSessionId: clientSessionId,
    );
  }
}

void attachClientTelemetryDioInterceptor(Dio dio, {ClientTelemetryService? telemetry}) {
  final hasTelemetryInterceptor = dio.interceptors.any((interceptor) => interceptor is ClientTelemetryDioInterceptor);
  if (hasTelemetryInterceptor) {
    return;
  }

  dio.interceptors.add(ClientTelemetryDioInterceptor(telemetry: telemetry));
}
