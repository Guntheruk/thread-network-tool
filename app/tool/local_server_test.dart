import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_server.dart';

void check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

Future<void> fails(Future<Object?> Function() action, String code) async {
  try {
    await action();
  } on ApiFailure catch (error) {
    check(error.code == code, 'unexpected failure');
    return;
  }
  throw StateError('expected $code');
}

Future<void> main() async {
  var calls = 0;
  var instant = DateTime.utc(2026, 1, 1);
  var probeReply = const NativeReply(0, {
    'schema_version': 1,
    'probe_status': 'completed',
    'authenticated': true,
    'identity_match': 'match',
    'active_status': 'read',
    'pending_status': 'empty',
    'network_key': 'must-never-leak',
  });
  Completer<void>? blocker;
  final session = LiveSession((args, credential) async {
    calls++;
    if (blocker != null) await blocker.future;
    switch (args.first) {
      case 'inspect':
        check(credential == 'aabb', 'credential must use stdin input');
        return const NativeReply(0,
            {'schema_version': 1, 'valid': true, 'network_name': 'FixtureNet'});
      case 'discover':
        check(credential == null, 'discovery must not receive credentials');
        return const NativeReply(0, {
          'schema_version': 1,
          'discovery_status': 'completed',
          'routers': [
            {
              'service_name': 'FixtureRouter',
              'network_name': 'FixtureNet',
              'thread_version': '1.4.0',
              'address': '192.168.99.11',
              'port': 49155,
              'secret': 'must-never-leak'
            },
            {
              'service_name': 'ExternalRouter',
              'address': '8.8.8.8',
              'port': 443
            },
          ]
        });
      case 'probe':
        check(
            args.length == 3 &&
                args[1] == '192.168.99.11' &&
                args[2] == '49155',
            'allowlisted endpoint');
        check(credential == 'aabb', 'probe credential');
        return probeReply;
      default:
        throw StateError('non-read command');
    }
  }, now: () => instant);
  await fails(() => session.perform('credentials', {'dataset': 'secret\ntext'}),
      'invalid_credentials');
  check(calls == 0, 'invalid input reached engine');
  await session.perform('credentials', {'dataset': 'aabb'});
  await session.perform('discover', {});
  final routers = session.state['routers'] as List;
  final id = routers.first['id'];
  check(routers[1]['endpoint_usable'] == false,
      'public internet endpoint accepted');
  await fails(() => session.perform('probe', {'router_id': routers[1]['id']}),
      'unsupported_endpoint');
  await fails(() => session.perform('probe', {'router_id': '192.168.99.11'}),
      'unknown_router');
  await session.perform('probe', {'router_id': id});
  check(
      (session.state['routers'] as List).first['probe']['identity_match'] ==
          'match',
      'successful probe lost');
  final encoded = jsonEncode(session.state);
  check(
      !encoded.contains('must-never-leak') &&
          !encoded.contains('aabb') &&
          !encoded.contains('192.168.99.11'),
      'private output leaked');
  probeReply =
      const NativeReply(124, {'schema_version': 1, 'probe_status': 'timeout'});
  await session.perform('probe', {'router_id': id});
  check(
      (session.state['routers'] as List).first['probe']['authenticated'] ==
          'unknown',
      'timeout claimed authentication');
  probeReply = const NativeReply(1, {
    'probe_status': 'completed',
    'authenticated': true,
    'identity_match': 'match',
    'active_status': 'read',
    'pending_status': 'empty'
  });
  await session.perform('probe', {'router_id': id});
  check(
      (session.state['routers'] as List).first['probe']['probe_status'] ==
          'partial',
      'bad exit accepted');
  instant = instant.add(const Duration(minutes: 6));
  await fails(
      () => session.perform('probe', {'router_id': id}), 'discovery_expired');
  await session.perform('discover', {});
  await fails(
      () => session.perform('probe', {'router_id': id}), 'unknown_router');
  blocker = Completer<void>();
  final pending = session.perform('discover', {});
  await fails(() => session.perform('discover', {}), 'busy');
  blocker.complete();
  await pending;
  blocker = null;

  final root = await Directory.systemTemp.createTemp('tnt-http-test-');
  final web = await Directory('${root.path}/web').create();
  final privatePath = '${root.path}/session.json';
  await writePrivateSessionFile(privatePath, 'private-fixture-token');
  check((await File(privatePath).stat()).mode & 0x3f == 0,
      'session file permissions');
  try {
    await writePrivateSessionFile(privatePath, 'replacement');
    throw StateError('existing session file replaced');
  } on FileSystemException {/* Expected: exclusive publication. */}
  check(await File(privatePath).readAsString() == 'private-fixture-token',
      'session overwritten');
  await File('${web.path}/index.html').writeAsString('<p>fixture</p>');
  await File('${root.path}/private.txt').writeAsString('must-never-leak');
  await Link('${web.path}/escape.txt').create('${root.path}/private.txt');
  final app = await LocalServer.start(
      session: session, webRoot: web.path, port: 0, token: '0' * 64);
  final client = HttpClient();
  Future<(int, String)> request(String path,
      {String method = 'GET',
      bool auth = true,
      String? origin,
      String? host,
      String? body}) async {
    final req = await client.openUrl(method, Uri.parse('${app.origin}$path'));
    if (auth) req.headers.set('Authorization', 'Bearer ${'0' * 64}');
    if (origin != null) req.headers.set('Origin', origin);
    if (host != null) req.headers.set('Host', host);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(body);
    }
    final response = await req.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  }

  try {
    check((await request('/api/state', auth: false)).$1 == 401,
        'missing bearer accepted');
    check(
        (await request('/api/state', origin: 'https://example.com')).$1 == 403,
        'foreign origin accepted');
    check((await request('/api/state', host: 'attacker.test')).$1 == 403,
        'rebinding host accepted');
    check((await request('/api/state')).$1 == 200, 'authorized state failed');
    check((await request('/api/join', method: 'POST', body: '{}')).$1 == 404,
        'mutation route exists');
    check(
        (await request('/api/credentials',
                    method: 'POST', body: jsonEncode({'dataset': 'x' * 3000})))
                .$1 ==
            413,
        'body limit failed');
    check(
        (await request('/api/credentials',
                    method: 'POST', body: '{"dataset":"secret"}'))
                .$2 ==
            '{"error":"invalid_credentials"}',
        'error echoed input');
    check((await request('/')).$2 == '<p>fixture</p>', 'static file missing');
    check((await request('/escape.txt')).$1 == 404, 'symlink escaped web root');
    check((await request('/api/state')).$2.contains('must-never-leak') == false,
        'API leaked raw native result');
    final slow =
        await Socket.connect(InternetAddress.loopbackIPv4, app.server.port);
    final received = <int>[];
    final closed = Completer<void>();
    slow.listen(received.addAll,
        onDone: () => closed.complete(),
        onError: (_) {
          if (!closed.isCompleted) closed.complete();
        });
    final elapsed = Stopwatch()..start();
    slow.write(
        'POST /api/discover HTTP/1.1\r\nHost: 127.0.0.1:${app.server.port}\r\n'
        'Authorization: Bearer ${'0' * 64}\r\nContent-Type: application/json\r\n'
        'Content-Length: 100\r\n\r\n{');
    final drip = Timer.periodic(
        const Duration(milliseconds: 600), (_) => slow.write(' '));
    try {
      await closed.future.timeout(const Duration(seconds: 7));
      // Cancelling an incomplete HttpRequest may close its socket before a
      // response can be written. Both closure and 408 enforce the deadline.
      check(
          received.isEmpty || utf8.decode(received).startsWith('HTTP/1.1 408 '),
          'unexpected body deadline response');
      check(
          elapsed.elapsed >= const Duration(seconds: 4) &&
              elapsed.elapsed < const Duration(seconds: 7),
          'body deadline extended by chunks');
    } finally {
      drip.cancel();
      slow.destroy();
    }
  } finally {
    client.close(force: true);
    await app.close();
    await root.delete(recursive: true);
  }
  check(
      localEndpoint('127.0.0.1') == false &&
          localEndpoint('224.0.0.1') == false &&
          localEndpoint('fe80::1') == false &&
          localEndpoint('fd12::1') &&
          localEndpoint('10.1.2.3'),
      'IP policy');
  stdout.writeln(
      'PASS: session, endpoint binding, deadlines/statuses, redaction and HTTP access boundaries');
}
