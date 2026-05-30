import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/store.repository.dart';
import 'package:immich_mobile/services/telemetry/client_telemetry.service.dart';

class _InMemoryStoreRepository implements IStoreRepository {
  final Map<int, Object?> _values = <int, Object?>{};
  final StreamController<void> _updates = StreamController<void>.broadcast();

  List<StoreDto<Object>> _snapshot() {
    return _values.entries
        .map((entry) {
          final key = StoreKey.values.firstWhere((candidate) => candidate.id == entry.key) as StoreKey<Object>;
          return StoreDto<Object>(key, entry.value);
        })
        .toList(growable: false);
  }

  @override
  Future<bool> deleteAll() async {
    _values.clear();
    _updates.add(null);
    return true;
  }

  @override
  Future<void> delete<T>(StoreKey<T> key) async {
    _values.remove(key.id);
    _updates.add(null);
  }

  @override
  Future<List<StoreDto<Object>>> getAll() async {
    return _snapshot();
  }

  @override
  Future<T?> tryGet<T>(StoreKey<T> key) async {
    return _values[key.id] as T?;
  }

  @override
  Future<bool> upsert<T>(StoreKey<T> key, T value) async {
    _values[key.id] = value;
    _updates.add(null);
    return true;
  }

  @override
  Stream<List<StoreDto<Object>>> watchAll() async* {
    yield _snapshot();
    yield* _updates.stream.map((_) => _snapshot());
  }

  @override
  Stream<T?> watch<T>(StoreKey<T> key) async* {
    yield _values[key.id] as T?;
    yield* _updates.stream.map((_) => _values[key.id] as T?);
  }
}

void main() {
  const packageInfoChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
  final telemetry = ClientTelemetryService.I;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(packageInfoChannel, (
      MethodCall methodCall,
    ) async {
      if (methodCall.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'Pizcloud Photos',
          'packageName': 'com.pizcloud.photos',
          'version': '1.2.3',
          'buildNumber': '456',
          'buildSignature': 'test-signature',
          'installerStore': 'play_store',
        };
      }
      return null;
    });

    await StoreService.init(storeRepository: _InMemoryStoreRepository());
  });

  tearDown(() async {
    await Store.clear();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      packageInfoChannel,
      null,
    );
  });

  group('redaction', () {
    test('redacts sensitive fields by key path', () {
      final payload =
          telemetry.redactForTelemetry(<String, dynamic>{
                'email': 'alice@example.com',
                'purchaseToken': 'purchase-token-1234567890',
                'orderId': 'order-id-1234567890',
                'nested': <String, dynamic>{'authorization': 'Bearer abcdefghijklmnop'},
              })
              as Map<String, dynamic>;

      expect(payload['email'], 'a***@example.com');
      expect(payload['purchaseToken'], isNot('purchase-token-1234567890'));
      expect(payload['orderId'], isNot('order-id-1234567890'));
      expect((payload['nested'] as Map<String, dynamic>)['authorization'], 'Bea***op');
    });

    test('redacts email and bearer token in free-form strings', () {
      final payload =
          telemetry.redactForTelemetry(<String, dynamic>{
                'error':
                    'failed for user bob@example.com with Bearer super-secret-token and jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signedpayload',
              })
              as Map<String, dynamic>;

      final error = payload['error'] as String;
      expect(error.contains('bob@example.com'), isFalse);
      expect(error.contains('b***@example.com'), isTrue);
      expect(error.contains('super-secret-token'), isFalse);
      expect(error.contains('Bearer ***'), isTrue);
      expect(error.contains('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signedpayload'), isFalse);
      expect(error.contains('***.***.***'), isTrue);
    });
  });

  group('headers', () {
    test('attaches correlation headers and normalizes event name', () async {
      final headers = <String, dynamic>{};
      final meta = await telemetry.attachHeadersToMap(headers, eventName: 'notifications.device.register invalid/name');

      expect(meta, isNotNull);
      expect(headers['x-request-id'], isNotNull);
      expect(headers['x-correlation-id'], isNotNull);
      expect(headers['x-client-event-id'], isNotNull);
      expect(headers['x-client-session-id'], isNotNull);
      expect(headers['x-client-event-name'], 'notifications.device.register_invalid_name');
      expect(headers['x-client-app-version'], '1.2.3');
      expect(headers['x-client-build-number'], '456');
    });

    test('does not override existing telemetry headers', () async {
      final headers = <String, dynamic>{
        'x-request-id': 'req_keep',
        'x-correlation-id': 'cid_keep',
        'x-client-event-id': 'evt_keep',
        'x-client-session-id': 'sid_keep',
        'x-client-event-name': 'existing.event',
      };

      final meta = await telemetry.attachHeadersToMap(headers, eventName: 'auth.login.submit');

      expect(meta, isNotNull);
      expect(headers['x-request-id'], 'req_keep');
      expect(headers['x-correlation-id'], 'cid_keep');
      expect(headers['x-client-event-id'], 'evt_keep');
      expect(headers['x-client-session-id'], 'sid_keep');
      expect(headers['x-client-event-name'], 'existing.event');
    });

    test('runtime override can disable telemetry header attachment', () async {
      await Store.put(StoreKey.clientTelemetryEnabled, false);
      final headers = <String, dynamic>{'accept': 'application/json'};

      final meta = await telemetry.attachHeadersToMap(headers, eventName: 'auth.login.submit');

      expect(meta, isNull);
      expect(headers['accept'], 'application/json');
      expect(headers.containsKey('x-request-id'), isFalse);
      expect(headers.containsKey('x-correlation-id'), isFalse);
      expect(headers.containsKey('x-client-event-id'), isFalse);
      expect(headers.containsKey('x-client-session-id'), isFalse);
      expect(headers.containsKey('x-client-event-name'), isFalse);
    });
  });
}
