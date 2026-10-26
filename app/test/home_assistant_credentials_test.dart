import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/home_assistant_credentials.dart';
import 'package:thread_network_tool/home_assistant_credentials_io.dart';

import 'support/home_assistant_stub.dart';
import 'support/home_assistant_tls.dart';

Matcher failure(HomeAssistantFailure code) =>
    isA<HomeAssistantCredentialException>()
        .having((e) => e.failure, 'fixed failure', code);

void main() {
  late HaTlsFixture tls;
  setUpAll(() async {
    tls = await HaTlsFixture.create();
  });
  tearDownAll(() => tls.close());
  test(
      'real websocket authenticates, lists, and fetches only selected nonpreferred ID',
      () async {
    final stub = await HaStub.start();
    final provider = HomeAssistantCredentials();
    addTearDown(stub.close);
    addTearDown(provider.cancel);
    final networks =
        await provider.connectAndList(stub.url, token, allowUnencrypted: true);
    expect(networks.map((n) => n.name), ['LabOne', 'LabTwo']);
    expect(
        stub.commands.map((m) => m['type']), ['auth', 'thread/list_datasets']);
    final value = await provider.fetchDataset(networks[1]);
    expect(value, dataset('LabTwo', '8899aabbccddeeff', 20));
    expect(stub.commands.map((m) => m['type']),
        ['auth', 'thread/list_datasets', 'thread/get_dataset_tlv']);
    expect(stub.commands.last['dataset_id'], 'second');
  });

  test('HTTP hostname resolves once and dials the exact validated private IP',
      () async {
    final stub = await HaStub.start();
    addTearDown(stub.close);
    var lookups = 0;
    final provider = IoHomeAssistantCredentials(lookup: (host) async {
      expect(host, 'rebind.invalid');
      lookups++;
      return [InternetAddress(lookups == 1 ? '127.0.0.1' : '8.8.8.8')];
    });
    addTearDown(provider.cancel);
    final networks = await provider.connectAndList(
        'http://rebind.invalid:${stub.server.port}', token,
        allowUnencrypted: true);
    expect(networks.length, 2);
    expect(lookups, 1);
    expect(stub.authenticated, true);
  });

  test('mixed public/private HTTP DNS answers are refused before connecting',
      () async {
    final stub = await HaStub.start();
    addTearDown(stub.close);
    final provider = IoHomeAssistantCredentials(
        lookup: (_) async =>
            [InternetAddress('127.0.0.1'), InternetAddress('8.8.8.8')]);
    await expectLater(
        provider.connectAndList(
            'http://rebind.invalid:${stub.server.port}', token,
            allowUnencrypted: true),
        throwsA(failure(HomeAssistantFailure.publicHttpRefused)));
    expect(stub.commands, isEmpty);
  });

  test(
      'HTTPS to plaintext refuses before sending authentication without HTTP consent',
      () async {
    final stub = await HaStub.start();
    addTearDown(stub.close);
    final provider =
        HomeAssistantCredentials(timeout: const Duration(seconds: 2));
    addTearDown(provider.cancel);
    await expectLater(
        provider.connectAndList('https://127.0.0.1:${stub.server.port}', token),
        throwsA(failure(HomeAssistantFailure.connectionFailed)));
    expect(stub.authenticated, false);
    expect(stub.commands, isEmpty);
  });

  test(
      'HTTPS with trusted test CA and original hostname lists and imports selected network',
      () async {
    final stub = await HaStub.start(securityContext: tls.serverContext);
    addTearDown(stub.close);
    var lookups = 0;
    final provider = IoHomeAssistantCredentials(
      securityContext: tls.clientContext,
      lookup: (host) async {
        expect(host, 'localhost');
        lookups++;
        // Return only a numeric destination: TLS must still verify the URL hostname.
        return [InternetAddress('127.0.0.1')];
      },
    );
    addTearDown(provider.cancel);
    final networks = await provider.connectAndList(
        'https://localhost:${stub.server.port}', token);
    expect(stub.authenticated, true);
    expect(lookups, 1);
    expect(await provider.fetchDataset(networks[1]),
        dataset('LabTwo', '8899aabbccddeeff', 20));
    expect(stub.commands.last['dataset_id'], 'second');
  });

  test(
      'trusted TLS certificate for a different hostname is rejected before auth',
      () async {
    final stub = await HaStub.start(securityContext: tls.serverContext);
    addTearDown(stub.close);
    final provider =
        IoHomeAssistantCredentials(securityContext: tls.clientContext);
    addTearDown(provider.cancel);
    // The certificate is trusted but has DNS:localhost only, not this IP SAN.
    await expectLater(
        provider.connectAndList('https://127.0.0.1:${stub.server.port}', token),
        throwsA(failure(HomeAssistantFailure.connectionFailed)));
    expect(stub.commands, isEmpty);
    expect(stub.authenticated, false);
  });

  test('production OS trust rejects the synthetic CA with correct hostname',
      () async {
    final stub = await HaStub.start(securityContext: tls.serverContext);
    addTearDown(stub.close);
    final provider = IoHomeAssistantCredentials(
        lookup: (host) async => (await InternetAddress.lookup(host))
            .where((a) => a.type == InternetAddressType.IPv4)
            .toList());
    addTearDown(provider.cancel);
    await expectLater(
        provider.connectAndList('https://localhost:${stub.server.port}', token),
        throwsA(failure(HomeAssistantFailure.connectionFailed)));
    expect(stub.commands, isEmpty);
    expect(stub.authenticated, false);
  });

  for (final cancel in [true, false]) {
    test(
        '${cancel ? 'cancellation' : 'deadline'} closes an in-progress TLS connection',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final hello = Completer<void>();
      final closed = Completer<void>();
      final sockets = <Socket>[];
      server.listen((socket) {
        sockets.add(socket);
        socket.listen((bytes) {
          // A real TLS client hello, never a plaintext HTTP GET.
          expect(bytes.first, 22);
          expect(
              utf8.decode(bytes, allowMalformed: true), isNot(contains(token)));
          if (!hello.isCompleted) hello.complete();
        }, onDone: () {
          if (!closed.isCompleted) closed.complete();
        }, onError: (_) {
          if (!closed.isCompleted) closed.complete();
        });
        // Deliberately withhold the server TLS handshake.
      });
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      });
      final provider = IoHomeAssistantCredentials(
          timeout: Duration(milliseconds: cancel ? 3000 : 150));
      addTearDown(provider.cancel);
      final outcome = expectLater(
          provider.connectAndList('https://127.0.0.1:${server.port}', token),
          throwsA(failure(cancel
              ? HomeAssistantFailure.cancelled
              : HomeAssistantFailure.timedOut)));
      await hello.future.timeout(const Duration(seconds: 1));
      if (cancel) provider.cancel();
      await outcome;
      // This checks remote EOF, not merely a completed caller Future.
      await closed.future.timeout(const Duration(seconds: 1));
    });
  }

  test('cancellation during DNS prevents a late TCP/TLS connection', () async {
    final stub = await HaStub.start(securityContext: tls.serverContext);
    addTearDown(stub.close);
    final lookup = Completer<List<InternetAddress>>();
    final started = Completer<void>();
    final provider = IoHomeAssistantCredentials(
        lookup: (_) {
          started.complete();
          return lookup.future;
        },
        securityContext: tls.clientContext);
    final outcome = expectLater(
        provider.connectAndList('https://localhost:${stub.server.port}', token),
        throwsA(failure(HomeAssistantFailure.cancelled)));
    await started.future;
    provider.cancel();
    await outcome;
    lookup.complete((await InternetAddress.lookup('localhost'))
        .where((a) => a.type == InternetAddressType.IPv4)
        .toList());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(stub.commands, isEmpty);
  });

  test('HTTP requires explicit consent before opening connection', () async {
    final stub = await HaStub.start();
    addTearDown(stub.close);
    final provider = HomeAssistantCredentials();
    await expectLater(provider.connectAndList(stub.url, token),
        throwsA(failure(HomeAssistantFailure.unencryptedConsentRequired)));
    expect(stub.commands, isEmpty);
  });

  test('public HTTP and mapped public IPs are refused without authentication',
      () async {
    for (final host in ['8.8.8.8', '203.0.113.1', '[::ffff:8.8.8.8]']) {
      await expectLater(
          HomeAssistantCredentials()
              .connectAndList('http://$host', token, allowUnencrypted: true),
          throwsA(failure(HomeAssistantFailure.publicHttpRefused)));
    }
  });

  test('private policy is narrow and handles IPv4 mapped IPv6', () {
    for (final address in [
      '127.0.0.1',
      '10.1.2.3',
      '172.16.2.3',
      '192.168.1.1',
      '::1',
      'fd00::1234',
      '::ffff:192.168.1.2'
    ]) {
      expect(isPrivateHomeAssistantAddress(InternetAddress(address)), true);
    }
    for (final address in [
      '0.0.0.0',
      '172.32.1.1',
      '169.254.169.254',
      '224.0.0.1',
      '8.8.8.8',
      '2001:db8::1',
      'fe80::1',
      '::ffff:8.8.8.8'
    ]) {
      expect(isPrivateHomeAssistantAddress(InternetAddress(address)), false);
    }
  });

  test(
      'URLs cannot carry credentials, query, fragments, changed endpoint or scheme',
      () async {
    for (final url in [
      'http://user:secret@localhost',
      'https://ha.invalid/?token=secret',
      'https://ha.invalid/#secret',
      'https://ha.invalid/other',
      'file:///tmp/a',
      'ws://localhost',
      'http://localhost:0',
      'not a URL'
    ]) {
      await expectLater(
          HomeAssistantCredentials()
              .connectAndList(url, token, allowUnencrypted: true),
          throwsA(failure(HomeAssistantFailure.invalidUrl)));
    }
  });

  test('redirects never reach another origin or send authentication', () async {
    var targetRequests = 0;
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target.listen((request) {
      targetRequests++;
      request.response.close();
    });
    final redirect = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    redirect.listen((request) {
      request.response.statusCode = 302;
      request.response.headers
          .set('location', 'http://127.0.0.1:${target.port}/api/websocket');
      request.response.close();
    });
    addTearDown(() => target.close(force: true));
    addTearDown(() => redirect.close(force: true));
    await expectLater(
        HomeAssistantCredentials().connectAndList(
            'http://127.0.0.1:${redirect.port}', token,
            allowUnencrypted: true),
        throwsA(failure(HomeAssistantFailure.connectionFailed)));
    expect(targetRequests, 0);
  });

  test('auth rejection is fixed and strips server messages', () async {
    final stub = await HaStub.start(handler: (s, ws, message) {
      ws.add(jsonEncode(
          {'type': 'auth_invalid', 'message': '$token SECRET_DATASET'}));
    });
    addTearDown(stub.close);
    try {
      await HomeAssistantCredentials()
          .connectAndList(stub.url, token, allowUnencrypted: true);
      fail('Expected rejection');
    } catch (error) {
      expect(error, failure(HomeAssistantFailure.authenticationRejected));
      expect(error.toString(), isNot(contains(token)));
      expect(error.toString(), isNot(contains('SECRET_DATASET')));
      expect(error.toString(), isNot(contains(stub.url)));
    }
  });

  for (final entry in {
    'unauthorized': HomeAssistantFailure.adminRequired,
    'unknown_command': HomeAssistantFailure.threadUnavailable,
    'not_found': HomeAssistantFailure.networkNotFound,
  }.entries) {
    test('typed server error ${entry.key} is redacted', () async {
      final stub = await HaStub.start(handler: (s, ws, message) {
        if (message['type'] == 'auth') {
          s.reply(ws, message);
          return;
        }
        ws.add(jsonEncode({
          'id': message['id'],
          'type': 'result',
          'success': false,
          'error': {'code': entry.key, 'message': '$token SECRET_DATASET'}
        }));
      });
      addTearDown(stub.close);
      await expectLater(
          HomeAssistantCredentials()
              .connectAndList(stub.url, token, allowUnencrypted: true),
          throwsA(failure(entry.value)));
    });
  }

  test('empty store is distinct from missing integration', () async {
    final stub = await HaStub.start(handler: (s, ws, message) {
      if (message['type'] == 'auth') {
        s.reply(ws, message);
        return;
      }
      s.result(ws, message, {'datasets': []});
    });
    addTearDown(stub.close);
    final provider = HomeAssistantCredentials();
    addTearDown(provider.cancel);
    expect(
        await provider.connectAndList(stub.url, token, allowUnencrypted: true),
        isEmpty);
  });

  test('a forged selection cannot request any dataset', () async {
    final stub = await HaStub.start();
    addTearDown(stub.close);
    final provider = HomeAssistantCredentials();
    await provider.connectAndList(stub.url, token, allowUnencrypted: true);
    await expectLater(
        provider.fetchDataset(const HomeAssistantNetwork(
            id: 'second',
            name: 'LabTwo',
            extendedPanId: '8899aabbccddeeff',
            channel: 20,
            panId: '1234')),
        throwsA(failure(HomeAssistantFailure.networkNotFound)));
    expect(stub.commands.length, 2);
  });

  for (final payload in [
    {'datasets': List.filled(65, rows.first)},
    {
      'datasets': [rows.first, rows.first]
    },
    {
      'datasets': [
        {
          'dataset_id': 'x',
          'network_name': 'Bad\nName',
          'extended_pan_id': '0011223344556677',
          'channel': 15
        }
      ]
    },
    {
      'datasets': [
        {
          'dataset_id': 'x',
          'network_name': 'LabOne',
          'extended_pan_id': 'bad',
          'channel': 15
        }
      ]
    },
    {
      'datasets': [
        {
          'dataset_id': 'x',
          'network_name': 'LabOne',
          'extended_pan_id': '0011223344556677',
          'channel': null
        }
      ]
    },
  ]) {
    test('malformed/bounded list fails closed ${payload.hashCode}', () async {
      final stub = await HaStub.start(handler: (s, ws, message) {
        if (message['type'] == 'auth') {
          s.reply(ws, message);
          return;
        }
        s.result(ws, message, payload);
      });
      addTearDown(stub.close);
      await expectLater(
          HomeAssistantCredentials()
              .connectAndList(stub.url, token, allowUnencrypted: true),
          throwsA(failure(HomeAssistantFailure.invalidData)));
    });
  }

  for (final entry in {
    'invalid': 'GG',
    'oversized': '00' * 255,
    'duplicate': '${dataset('LabTwo', '8899aabbccddeeff', 20)}0003000014',
    'mismatched name': dataset('Other', '8899aabbccddeeff', 20),
    'mismatched channel': dataset('LabTwo', '8899aabbccddeeff', 15),
    'mismatched xpan': dataset('LabTwo', '0011223344556677', 20),
    'mismatched pan': dataset('LabTwo', '8899aabbccddeeff', 20)
        .replaceFirst('01021234', '01025678'),
  }.entries) {
    test('fetched TLV ${entry.key} cannot pass to import', () async {
      final stub = await HaStub.start(handler: (s, ws, message) {
        if (message['type'] != 'thread/get_dataset_tlv') {
          s.reply(ws, message);
          return;
        }
        s.result(ws, message, {'tlv': entry.value});
      });
      addTearDown(stub.close);
      final provider = HomeAssistantCredentials();
      final networks = await provider.connectAndList(stub.url, token,
          allowUnencrypted: true);
      await expectLater(
          provider.fetchDataset(networks[1]),
          throwsA(failure(entry.key.startsWith('mismatched')
              ? HomeAssistantFailure.identityMismatch
              : HomeAssistantFailure.invalidData)));
    });
  }

  test('cancel during fetch closes connection and suppresses late dataset',
      () async {
    final requested = Completer<void>();
    final stub = await HaStub.start(handler: (s, ws, message) {
      if (message['type'] != 'thread/get_dataset_tlv') {
        s.reply(ws, message);
        return;
      }
      requested.complete();
    });
    addTearDown(stub.close);
    final provider = HomeAssistantCredentials();
    final networks =
        await provider.connectAndList(stub.url, token, allowUnencrypted: true);
    final future = provider.fetchDataset(networks[1]);
    final expectation =
        expectLater(future, throwsA(failure(HomeAssistantFailure.cancelled)));
    await requested.future;
    provider.cancel();
    await expectation;
  });

  test('one total deadline bounds handshake/auth/list together', () async {
    final stub = await HaStub.start(greet: false);
    addTearDown(stub.close);
    await expectLater(
        HomeAssistantCredentials(timeout: const Duration(milliseconds: 40))
            .connectAndList(stub.url, token, allowUnencrypted: true),
        throwsA(failure(HomeAssistantFailure.timedOut)));
    expect(stub.commands, isEmpty);
  });

  test('fetch has its own total deadline', () async {
    final stub = await HaStub.start(handler: (s, ws, message) {
      if (message['type'] != 'thread/get_dataset_tlv') s.reply(ws, message);
    });
    addTearDown(stub.close);
    final provider =
        HomeAssistantCredentials(timeout: const Duration(milliseconds: 100));
    final networks =
        await provider.connectAndList(stub.url, token, allowUnencrypted: true);
    await expectLater(provider.fetchDataset(networks[1]),
        throwsA(failure(HomeAssistantFailure.timedOut)));
  });

  test('fragmented messages are bounded before WebSocket aggregation',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close(force: true);
    });
    server.listen((request) async {
      final key = request.headers.value('sec-websocket-key')!;
      final digest =
          await Process.start('openssl', ['dgst', '-sha1', '-binary']);
      digest.stdin.write('$key' '258EAFA5-E914-47DA-95CA-C5AB0DC85B11');
      await digest.stdin.close();
      final hash = await digest.stdout.expand((bytes) => bytes).toList();
      expect(await digest.exitCode, 0);
      request.response.statusCode = 101;
      request.response.headers.set('connection', 'Upgrade');
      request.response.headers.set('upgrade', 'websocket');
      request.response.headers.set('sec-websocket-accept', base64Encode(hash));
      final socket = await request.response.detachSocket();
      sockets.add(socket);
      socket.listen((_) {}, onError: (_) {});
      // Every frame is under 32 KiB; only their combined message is too large.
      for (var i = 0; i < 3; i++) {
        final length = i == 2 ? 1000 : 16000;
        final header = [
          i == 0 ? 1 : (i == 2 ? 128 : 0),
          126,
          length >> 8,
          length & 255
        ];
        socket.add(header);
        socket.add(List.filled(length, 32));
      }
      await socket.flush();
    });
    await expectLater(
        HomeAssistantCredentials().connectAndList(
            'http://127.0.0.1:${server.port}', token,
            allowUnencrypted: true),
        throwsA(failure(HomeAssistantFailure.connectionFailed)));
  });

  test('oversized frame is rejected by bounded WebSocket parser', () async {
    final stub = await HaStub.start(greeting: 'x' * 32769);
    addTearDown(stub.close);
    await expectLater(
        HomeAssistantCredentials()
            .connectAndList(stub.url, token, allowUnencrypted: true),
        throwsA(failure(HomeAssistantFailure.connectionFailed)));
    expect(stub.commands, isEmpty);
  });

  test('excessive JSON nesting and nonobject data fail closed', () async {
    for (final greeting in [
      '{"type":"auth_required","extra":${'[' * 17}0${']' * 17}}',
      '[]'
    ]) {
      final stub = await HaStub.start(greeting: greeting);
      try {
        await expectLater(
            HomeAssistantCredentials()
                .connectAndList(stub.url, token, allowUnencrypted: true),
            throwsA(failure(HomeAssistantFailure.invalidData)));
      } finally {
        await stub.close();
      }
    }
  });
}
