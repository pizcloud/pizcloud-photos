import 'package:http/http.dart' as http;
import 'package:immich_mobile/services/telemetry/client_telemetry.service.dart';

class TelemetryHttpClient extends http.BaseClient {
  TelemetryHttpClient({http.Client? inner, ClientTelemetryService? telemetry})
    : _inner = inner ?? http.Client(),
      _telemetry = telemetry ?? ClientTelemetryService.I;

  final http.Client _inner;
  final ClientTelemetryService _telemetry;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final eventName = _extractEventName(request.headers);
    ClientTelemetryMeta? meta;

    try {
      final nextHeaders = <String, dynamic>{};
      nextHeaders.addAll(request.headers);
      meta = await _telemetry.attachHeadersToMap(nextHeaders, eventName: eventName);
      nextHeaders.forEach((key, value) {
        request.headers[key] = value.toString();
      });
    } catch (_) {
      // fail-open
    }

    try {
      _telemetry.logHttpRequest(
        transport: 'http',
        method: request.method,
        uri: request.url,
        meta: meta,
        eventName: eventName,
      );
    } catch (_) {
      // fail-open
    }

    try {
      final response = await _inner.send(request);
      _telemetry.logHttpResponse(
        transport: 'http',
        method: request.method,
        uri: request.url,
        status: response.statusCode,
        durationMs: _durationMs(startedAt),
        meta: meta,
        eventName: eventName,
      );
      return response;
    } catch (error) {
      _telemetry.logHttpError(
        transport: 'http',
        method: request.method,
        uri: request.url,
        error: error,
        durationMs: _durationMs(startedAt),
        meta: meta,
        eventName: eventName,
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }

  int _durationMs(int startedAtMs) {
    final duration = DateTime.now().millisecondsSinceEpoch - startedAtMs;
    return duration < 0 ? 0 : duration;
  }

  String? _extractEventName(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'x-client-event-name') {
        continue;
      }

      final normalized = entry.value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
      return null;
    }

    return null;
  }
}
