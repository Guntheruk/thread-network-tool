import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/android_credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('thread_network/android_credentials_test');
  final calls = <String>[];

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('unsupported platform never calls native service', () async {
    final provider =
        AndroidCredentials(channel: channel, supportedPlatform: false);
    expect((await provider.availability()).status,
        AndroidCredentialStatus.unavailable);
    expect((await provider.fetchPreferred()).status,
        AndroidCredentialStatus.unavailable);
    expect(calls, isEmpty);
  });

  test('availability never returns a dataset', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {
        'status': 'available',
        'dataset': Uint8List.fromList([1, 2])
      };
    });
    final result = await AndroidCredentials(
      channel: channel,
      supportedPlatform: true,
    ).availability();
    expect(result.status, AndroidCredentialStatus.available);
    expect(result.datasetHex, isNull);
    expect(calls, ['availability']);
  });

  test('explicit fetch returns bounded dataset and redacted toString',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {
        'status': 'available',
        'dataset': Uint8List.fromList([0, 10, 255])
      };
    });
    final result = await AndroidCredentials(
      channel: channel,
      supportedPlatform: true,
    ).fetchPreferred();
    expect(result.status, AndroidCredentialStatus.available);
    expect(result.datasetHex, '000aff');
    expect(result.toString(), isNot(contains('000aff')));
    expect(calls, ['fetchPreferred']);
  });

  test('non-success states cannot carry a dataset', () async {
    final provider =
        AndroidCredentials(channel: channel, supportedPlatform: true);
    for (final entry in <String, AndroidCredentialStatus>{
      'unavailable': AndroidCredentialStatus.unavailable,
      'missingSdk': AndroidCredentialStatus.missingSdk,
      'notConfigured': AndroidCredentialStatus.notConfigured,
      'localNetworkDisconnected':
          AndroidCredentialStatus.localNetworkDisconnected,
      'permissionDenied': AndroidCredentialStatus.permissionDenied,
      'cancelled': AndroidCredentialStatus.cancelled,
      'busy': AndroidCredentialStatus.busy,
      'timedOut': AndroidCredentialStatus.timedOut,
    }.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              channel,
              (_) async => {
                    'status': entry.key,
                    'dataset': Uint8List.fromList([1, 2]),
                  });
      final result = await provider.fetchPreferred();
      expect(result.status, entry.value);
      expect(result.datasetHex, isNull);
    }
  });

  test('malformed success and unknown status fail closed', () async {
    final provider =
        AndroidCredentials(channel: channel, supportedPlatform: true);
    for (final response in [
      {'status': 'available'},
      {'status': 'available', 'dataset': Uint8List(0)},
      {'status': 'available', 'dataset': Uint8List(255)},
      {'status': 'available', 'dataset': 'private'},
      {
        'status': 'unknown',
        'dataset': Uint8List.fromList([1])
      },
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => response);
      final result = await provider.fetchPreferred();
      expect(result.status, AndroidCredentialStatus.failure);
      expect(result.datasetHex, isNull);
    }
  });

  test('platform errors do not expose message or details', () async {
    final provider =
        AndroidCredentials(channel: channel, supportedPlatform: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'permissionDenied',
        message: 'PRIVATE DATASET',
        details: 'PRIVATE KEY',
      );
    });
    final result = await provider.fetchPreferred();
    expect(result.status, AndroidCredentialStatus.permissionDenied);
    expect(result.datasetHex, isNull);
    expect(result.toString(), isNot(contains('PRIVATE')));
  });

  test('missing channel and timeout are bounded', () async {
    final provider =
        AndroidCredentials(channel: channel, supportedPlatform: true);
    expect((await provider.availability()).status,
        AndroidCredentialStatus.unavailable);
    final pending = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call.method);
      return call.method == 'fetchPreferred' ? pending.future : Future.value();
    });
    final result = await AndroidCredentials(
      channel: channel,
      supportedPlatform: true,
      fetchTimeout: const Duration(milliseconds: 1),
    ).fetchPreferred();
    expect(result.status, AndroidCredentialStatus.timedOut);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['fetchPreferred', 'cancelPending']);
    pending.complete({
      'status': 'available',
      'dataset': Uint8List.fromList([1])
    });
    expect(result.datasetHex, isNull);
  });

  test('cancel invalidates late bytes and a new fetch has a new operation ID',
      () async {
    final pending = Completer<Object?>();
    final operationIds = <String>[];
    String? cancelledId;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      if (call.method == 'fetchPreferred') {
        final id = (call.arguments as Map)['operationId'] as String;
        operationIds.add(id);
        if (operationIds.length == 1) return pending.future;
        return Future.value({
          'status': 'available',
          'dataset': Uint8List.fromList([3, 4]),
        });
      }
      if (call.method == 'cancelPending') {
        cancelledId = (call.arguments as Map)['operationId'] as String;
      }
      return Future.value();
    });
    final provider =
        AndroidCredentials(channel: channel, supportedPlatform: true);
    final first = provider.fetchPreferred();
    await Future<void>.delayed(Duration.zero);
    expect(
        (await provider.fetchPreferred()).status, AndroidCredentialStatus.busy);
    await provider.cancelPending();
    final cancelled = await first;
    expect(cancelled.status, AndroidCredentialStatus.cancelled);
    expect(cancelled.datasetHex, isNull);
    expect(cancelledId, operationIds.single);
    pending.complete({
      'status': 'available',
      'dataset': Uint8List.fromList([1, 2]),
    });
    await Future<void>.delayed(Duration.zero);
    expect(cancelled.datasetHex, isNull);
    final second = await provider.fetchPreferred();
    expect(second.datasetHex, '0304');
    expect(operationIds[1], isNot(operationIds[0]));
  });
}
