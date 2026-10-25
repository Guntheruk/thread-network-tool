import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/apple_credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('thread_network/apple_credentials_test');
  final calls = <String>[];

  setUp(() {
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('unsupported platform makes no channel calls', () async {
    final provider =
        AppleCredentials(channel: channel, supportedPlatform: false);
    expect((await provider.availability()).status,
        AppleCredentialStatus.unavailable);
    expect((await provider.fetchPreferred()).status,
        AppleCredentialStatus.unavailable);
    expect(calls, isEmpty);
  });

  test('availability checks only availability and returns no dataset',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {
        'status': 'available',
        'dataset': Uint8List.fromList([1, 2])
      };
    });
    final result =
        await AppleCredentials(channel: channel, supportedPlatform: true)
            .availability();
    expect(result.status, AppleCredentialStatus.available);
    expect(result.datasetHex, isNull);
    expect(calls, ['availability']);
  });

  test('explicit fetch returns only a valid dataset', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {
        'status': 'available',
        'dataset': Uint8List.fromList([0, 10, 255])
      };
    });
    final result =
        await AppleCredentials(channel: channel, supportedPlatform: true)
            .fetchPreferred();
    expect(result.status, AppleCredentialStatus.available);
    expect(result.datasetHex, '000aff');
    expect(calls, ['fetchPreferred']);
  });

  test('non-success states cannot carry a dataset', () async {
    for (final entry in <String, AppleCredentialStatus>{
      'unavailable': AppleCredentialStatus.unavailable,
      'noCredentials': AppleCredentialStatus.noCredentials,
      'permissionDenied': AppleCredentialStatus.permissionDenied,
      'accessNotConfigured': AppleCredentialStatus.accessNotConfigured,
      'timedOut': AppleCredentialStatus.timedOut,
      'failure': AppleCredentialStatus.failure,
    }.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              channel,
              (_) async => {
                    'status': entry.key,
                    'dataset': Uint8List.fromList([1, 2]),
                  });
      final result =
          await AppleCredentials(channel: channel, supportedPlatform: true)
              .fetchPreferred();
      expect(result.status, entry.value);
      expect(result.datasetHex, isNull);
    }
  });

  test('malformed success and unknown states fail closed', () async {
    final provider =
        AppleCredentials(channel: channel, supportedPlatform: true);
    for (final response in [
      {'status': 'available'},
      {'status': 'available', 'dataset': Uint8List(0)},
      {'status': 'available', 'dataset': 'secret'},
      {'status': 'available', 'dataset': Uint8List(255)},
      {
        'status': 'unrecognized',
        'dataset': Uint8List.fromList([1])
      },
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => response);
      final result = await provider.fetchPreferred();
      expect(result.status, AppleCredentialStatus.failure);
      expect(result.datasetHex, isNull);
    }
  });

  test('platform errors are mapped without exposing message or details',
      () async {
    final provider =
        AppleCredentials(channel: channel, supportedPlatform: true);
    for (final entry in <String, AppleCredentialStatus>{
      'permissionDenied': AppleCredentialStatus.permissionDenied,
      'accessNotConfigured': AppleCredentialStatus.accessNotConfigured,
      'unknown': AppleCredentialStatus.failure,
    }.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: entry.key,
          message: 'PRIVATE DATASET',
          details: 'PRIVATE KEY',
        );
      });
      final result = await provider.fetchPreferred();
      expect(result.status, entry.value);
      expect(result.datasetHex, isNull);
      expect(result.toString(), isNot(contains('PRIVATE')));
    }
  });

  test('missing bridge is unavailable', () async {
    final result =
        await AppleCredentials(channel: channel, supportedPlatform: true)
            .availability();
    expect(result.status, AppleCredentialStatus.unavailable);
  });

  test('pending calls time out and late datasets stay inaccessible', () async {
    for (final method in ['availability', 'fetchPreferred']) {
      final pending = Completer<Object?>();
      int? fetchId;
      int? cancelledId;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
        calls.add(call.method);
        if (call.method == 'fetchPreferred') {
          fetchId = (call.arguments as Map)['requestId'] as int;
        }
        if (call.method == 'cancelFetch') {
          cancelledId = (call.arguments as Map)['requestId'] as int;
          return Future<Object?>.value(null);
        }
        return pending.future;
      });
      final provider = AppleCredentials(
        channel: channel,
        supportedPlatform: true,
        availabilityTimeout: const Duration(milliseconds: 1),
        fetchTimeout: const Duration(milliseconds: 1),
      );
      final result = method == 'availability'
          ? await provider.availability()
          : await provider.fetchPreferred();
      expect(result.status, AppleCredentialStatus.timedOut);
      expect(result.datasetHex, isNull);
      if (method == 'availability') {
        expect(calls.last, 'availability');
      } else {
        expect(calls.sublist(calls.length - 2),
            ['fetchPreferred', 'cancelFetch']);
        expect(cancelledId, fetchId);
      }
      pending.complete({
        'status': 'available',
        'dataset': Uint8List.fromList([1, 2]),
      });
      expect(result.status, AppleCredentialStatus.timedOut);
      expect(result.datasetHex, isNull);
    }
    expect(calls, ['availability', 'fetchPreferred', 'cancelFetch']);
  });

  test('cancel invalidates a pending fetch and identifies its native request',
      () async {
    final pending = Completer<Object?>();
    int? fetchId;
    int? cancelledId;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      if (call.method == 'fetchPreferred') {
        fetchId = (call.arguments as Map)['requestId'] as int;
        return pending.future;
      }
      if (call.method == 'cancelFetch') {
        cancelledId = (call.arguments as Map)['requestId'] as int;
        return Future<Object?>.value(null);
      }
      fail('Unexpected call ${call.method}');
    });
    final provider =
        AppleCredentials(channel: channel, supportedPlatform: true);
    final fetch = provider.fetchPreferred();
    await Future<void>.delayed(Duration.zero);
    expect(fetchId, isNotNull);
    expect((await provider.fetchPreferred()).status,
        AppleCredentialStatus.inProgress);
    await provider.cancelFetch();
    expect(cancelledId, fetchId);
    pending.complete({
      'status': 'available',
      'dataset': Uint8List.fromList([0, 10, 255]),
    });
    final result = await fetch;
    expect(result.status, AppleCredentialStatus.cancelled);
    expect(result.datasetHex, isNull);
  });

  test('an old timeout cannot cancel a newer fetch', () async {
    final oldReply = Completer<Object?>();
    final newReply = Completer<Object?>();
    final oldCancelAck = Completer<Object?>();
    int? oldId;
    int? newId;
    int? cancelledId;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      if (call.method == 'fetchPreferred') {
        final id = (call.arguments as Map)['requestId'] as int;
        if (oldId == null) {
          oldId = id;
          return oldReply.future;
        }
        newId = id;
        return newReply.future;
      }
      if (call.method == 'cancelFetch') {
        cancelledId = (call.arguments as Map)['requestId'] as int;
        return oldCancelAck.future;
      }
      fail('Unexpected call ${call.method}');
    });
    final provider = AppleCredentials(
      channel: channel,
      supportedPlatform: true,
      fetchTimeout: const Duration(milliseconds: 200),
    );
    final first = provider.fetchPreferred();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(cancelledId, oldId);
    final second = provider.fetchPreferred();
    await Future<void>.delayed(Duration.zero);
    expect(newId, isNot(oldId));
    oldCancelAck.complete(null);
    expect((await first).status, AppleCredentialStatus.timedOut);
    newReply.complete({
      'status': 'available',
      'dataset': Uint8List.fromList([1, 2]),
    });
    expect((await second).datasetHex, '0102');
    oldReply.complete({
      'status': 'available',
      'dataset': Uint8List.fromList([9, 9]),
    });
  });
}
