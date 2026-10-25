import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:thread_network_tool/native/session.dart';
export 'package:thread_network_tool/native/session.dart';

Future<void> writePrivateSessionFile(String path, String contents) async {
  // The current local helper is tested on macOS. POSIX mkdtemp creates a
  // private directory; the final hard link publishes an already-private file.
  if (Platform.isWindows) throw const FileSystemException();
  final target = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const FileSystemException();
  }
  await target.parent.create(recursive: true);
  final staging = await target.parent.createTemp('.tnt-session-');
  try {
    if ((await staging.stat()).mode & 0x3f != 0) {
      throw const FileSystemException();
    }
    final source = File('${staging.path}/session.json');
    await source.create(exclusive: true);
    final chmod = await Process.run('/bin/chmod', ['600', source.path]);
    if (chmod.exitCode != 0) throw const FileSystemException();
    await source.writeAsString(contents, flush: true);
    // No -f: an existing destination must never be replaced.
    final publish = await Process.run('/bin/ln', [source.path, target.path]);
    if (publish.exitCode != 0) throw const FileSystemException();
  } finally {
    await staging.delete(recursive: true);
  }
}

class LocalServer {
  LocalServer._(this.server, this.session, this.webRoot, this.token);
  final HttpServer server;
  final LiveSession session;
  final String webRoot;
  final String token;
  String get origin => 'http://127.0.0.1:${server.port}';
  String get launchUrl => '$origin/#session=$token';

  static Future<LocalServer> start(
      {required LiveSession session,
      required String webRoot,
      int port = 5188,
      String? token}) async {
    final root = await Directory(webRoot).resolveSymbolicLinks();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.idleTimeout = const Duration(seconds: 45);
    server.serverHeader = null;
    final app = LocalServer._(server, session, root, token ?? randomToken());
    server.listen((request) {
      unawaited(app._handle(request));
    });
    return app;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('X-Frame-Options', 'DENY');
    response.headers.set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; worker-src 'self' blob:; "
            "frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
    try {
      if (request.headers.value('host') != '127.0.0.1:${server.port}') {
        throw const ApiFailure('forbidden', 403);
      }
      final originHeader = request.headers.value('origin');
      if (originHeader != null && originHeader != origin) {
        throw const ApiFailure('forbidden', 403);
      }
      if (request.uri.path.startsWith('/api/')) {
        if (request.headers.value('authorization') != 'Bearer $token') {
          throw const ApiFailure('unauthorized', 401);
        }
        if (request.method == 'GET' && request.uri.path == '/api/state') {
          _json(response, session.state);
        } else if (request.method == 'POST' &&
            {'/api/discover', '/api/credentials', '/api/probe'}
                .contains(request.uri.path)) {
          if (request.headers.contentType?.mimeType != 'application/json') {
            throw const ApiFailure('json_required', 415);
          }
          final body = await _body(request);
          _json(response,
              await session.perform(request.uri.path.substring(5), body));
        } else {
          throw const ApiFailure('not_found', 404);
        }
      } else {
        if (request.method != 'GET' && request.method != 'HEAD') {
          throw const ApiFailure('method_not_allowed', 405);
        }
        final segments = request.uri.pathSegments;
        if (segments.any((s) =>
            s.startsWith('.') ||
            s.contains('/') ||
            s.contains('\\') ||
            s.contains('\u0000'))) {
          throw const ApiFailure('not_found', 404);
        }
        final relative =
            request.uri.path == '/' ? 'index.html' : segments.join('/');
        final file = File('$webRoot/$relative');
        final resolved = await file.resolveSymbolicLinks();
        if (!resolved.startsWith('$webRoot${Platform.pathSeparator}') ||
            !await file.exists()) {
          throw const ApiFailure('not_found', 404);
        }
        final suffix = relative.split('.').last;
        const types = {
          'html': 'text/html',
          'js': 'application/javascript',
          'json': 'application/json',
          'wasm': 'application/wasm',
          'css': 'text/css',
          'png': 'image/png',
          'svg': 'image/svg+xml',
          'woff': 'font/woff',
          'woff2': 'font/woff2',
          'ttf': 'font/ttf',
          'otf': 'font/otf',
          'ico': 'image/x-icon'
        };
        response.headers
            .set('Content-Type', types[suffix] ?? 'application/octet-stream');
        if (request.method == 'GET') await response.addStream(file.openRead());
      }
    } on ApiFailure catch (error) {
      response.statusCode = error.status;
      response.persistentConnection = false;
      _json(response, {'error': error.code});
    } catch (_) {
      response.statusCode = 500;
      _json(response, {'error': 'request_failed'});
    } finally {
      await response.close();
    }
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final bytes = <int>[];
    final started = Stopwatch()..start();
    final iterator = StreamIterator(request);
    try {
      while (true) {
        final remaining = const Duration(seconds: 5) - started.elapsed;
        if (remaining <= Duration.zero) {
          throw const ApiFailure('request_timeout', 408);
        }
        final hasNext = await iterator.moveNext().timeout(remaining,
            onTimeout: () => throw const ApiFailure('request_timeout', 408));
        if (!hasNext) break;
        final chunk = iterator.current;
        if (bytes.length + chunk.length > 2048) {
          throw const ApiFailure('body_too_large', 413);
        }
        bytes.addAll(chunk);
      }
    } finally {
      await iterator.cancel();
    }
    try {
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {/* Return a fixed error without echoing the input. */}
    throw const ApiFailure('invalid_json', 400);
  }

  void _json(HttpResponse response, Map<String, dynamic> data) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
  }

  Future<void> close() async {
    session.clear();
    await server.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  LocalServer? running;
  try {
    final options = <String, String>{};
    var seed = false;
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--credential-stdin') {
        seed = true;
        continue;
      }
      if (!{
            '--engine',
            '--discovery-engine',
            '--web-root',
            '--port',
            '--session-file'
          }.contains(args[i]) ||
          i + 1 >= args.length) {
        throw const FormatException();
      }
      options[args[i]] = args[++i];
    }
    final engine = options['--engine'];
    final web = options['--web-root'];
    if (engine == null || web == null || !File(engine).isAbsolute) {
      throw const FormatException();
    }
    final discoveryEngine = options['--discovery-engine'];
    if (discoveryEngine != null && !File(discoveryEngine).isAbsolute) {
      throw const FormatException();
    }
    final session = LiveSession(
        NativeProcess(engine, discoveryExecutable: discoveryEngine).call);
    if (seed) {
      final input = <int>[];
      await for (final bytes in stdin.timeout(const Duration(seconds: 15))) {
        if (input.length + bytes.length > 510) throw const FormatException();
        input.addAll(bytes);
      }
      await session
          .perform('credentials', {'dataset': utf8.decode(input).trim()});
      input.fillRange(0, input.length, 0);
    }
    final app = await LocalServer.start(
        session: session,
        webRoot: web,
        port: int.parse(options['--port'] ?? '5188'));
    running = app;
    final sessionPath = options['--session-file'];
    if (sessionPath != null) {
      await writePrivateSessionFile(
          sessionPath, jsonEncode({'url': app.launchUrl, 'pid': pid}));
    }
    stdout.writeln(
        'Read-only helper ready at ${app.origin}. Use the private session URL to open the live interface.');
    if (sessionPath == null) stdout.writeln(app.launchUrl);
    ProcessSignal.sigint.watch().listen((_) async {
      await app.close();
      exit(0);
    });
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) async {
        await app.close();
        exit(0);
      });
    }
  } catch (_) {
    await running?.close();
    stderr.writeln(
        'Local helper could not start. Check paths, port and credential input.');
    exitCode = 1;
  }
}
