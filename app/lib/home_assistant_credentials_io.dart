import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'home_assistant_credentials.dart';
import 'home_assistant_tls_socket.dart';

HomeAssistantCredentials createHomeAssistantCredentials(Duration timeout) =>
    IoHomeAssistantCredentials(timeout: timeout);

/// Direct, read-only, origin-bound connection. No redirects, cookies, proxies,
/// persistent credentials, certificate overrides or reconnect/retry behavior.
class IoHomeAssistantCredentials implements HomeAssistantCredentials {
  IoHomeAssistantCredentials(
      {this.timeout = const Duration(seconds: 15),
      Future<List<InternetAddress>> Function(String)? lookup,
      SecurityContext? securityContext})
      : _lookup = lookup ?? InternetAddress.lookup,
        _securityContext = securityContext;
  final Future<List<InternetAddress>> Function(String) _lookup;
  // Test fixtures may trust a synthetic CA. The public/default provider passes
  // null, which preserves the platform trust store. No bad-certificate callback.
  final SecurityContext? _securityContext;
  final Duration timeout;
  _FixedOriginClient? _client;
  WebSocket? _socket;
  StreamIterator<dynamic>? _messages;
  List<HomeAssistantNetwork> _networks = const [];
  int _generation = 0;
  int _id = 0;
  bool _busy = false;
  Completer<void>? _cancelled;
  @override
  bool get supported => true;

  @override
  void cancel() {
    _generation++;
    _cancelled?.complete();
    _cancelled = null;
    _disposeConnection();
  }

  void _disposeConnection() {
    _networks = const [];
    _messages?.cancel();
    _messages = null;
    _socket?.close();
    _socket = null;
    _client?.close(force: true);
    _client = null;
  }

  void _check(int generation) {
    if (_generation != generation) {
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.cancelled);
    }
  }

  Future<T> _operation<T>(Future<T> Function(int) action) async {
    if (_busy) {
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
    }
    _busy = true;
    final generation = _generation;
    final cancelled = Completer<void>();
    _cancelled = cancelled;
    try {
      return await Future.any<T>([
        action(generation),
        cancelled.future.then<T>((_) =>
            throw const HomeAssistantCredentialException(
                HomeAssistantFailure.cancelled)),
      ]).timeout(timeout);
    } on TimeoutException {
      _generation++;
      _disposeConnection();
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.timedOut);
    } on HomeAssistantCredentialException {
      _disposeConnection();
      rethrow;
    } catch (_) {
      _disposeConnection();
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
    } finally {
      if (identical(_cancelled, cancelled)) _cancelled = null;
      _busy = false;
    }
  }

  @override
  Future<List<HomeAssistantNetwork>> connectAndList(String url, String token,
      {bool allowUnencrypted = false}) async {
    cancel();
    return _operation((generation) async {
      final uri =
          homeAssistantEndpoint(url, allowUnencrypted: allowUnencrypted);
      if (token.isEmpty ||
          token.length > 4096 ||
          RegExp(r'\s').hasMatch(token)) {
        throw const HomeAssistantCredentialException(
            HomeAssistantFailure.authenticationRejected);
      }
      final client = _FixedOriginClient(
          uri, () => _check(generation), _lookup, _securityContext);
      _client = client;
      final socket = await WebSocket.connect(
        uri
            .replace(
                scheme: uri.scheme == 'https' ? 'wss' : 'ws', port: uri.port)
            .toString(),
        customClient: client,
        compression: CompressionOptions.compressionOff,
      );
      if (_generation != generation) {
        await socket.close();
        _check(generation);
      }
      _socket = socket;
      _messages = StreamIterator(socket);
      final hello = await _next(generation);
      if (hello['type'] != 'auth_required') invalidHomeAssistantData();
      socket.add(jsonEncode({'type': 'auth', 'access_token': token}));
      final auth = await _next(generation);
      if (auth['type'] == 'auth_invalid') {
        throw const HomeAssistantCredentialException(
            HomeAssistantFailure.authenticationRejected);
      }
      if (auth['type'] != 'auth_ok') invalidHomeAssistantData();
      final result = await _request('thread/list_datasets', generation);
      _networks = decodeHomeAssistantNetworks(result);
      return _networks;
    });
  }

  @override
  Future<String> fetchDataset(HomeAssistantNetwork selected) =>
      _operation((generation) async {
        // Only an actual row from the latest list is eligible, never a caller's
        // forged ID/metadata or a preferred network inferred from the server.
        if (!_networks.any((row) => identical(row, selected))) {
          throw const HomeAssistantCredentialException(
              HomeAssistantFailure.networkNotFound);
        }
        final result = await _request('thread/get_dataset_tlv', generation,
            datasetId: selected.id);
        final dataset = decodeHomeAssistantDataset(result, selected);
        _check(generation);
        _disposeConnection();
        return dataset;
      });

  Future<Map<String, dynamic>> _next(int generation) async {
    _check(generation);
    final messages = _messages;
    if (messages == null || !await messages.moveNext()) {
      _check(generation);
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
    }
    _check(generation);
    final raw = messages.current;
    if (raw is! String ||
        raw.length > 32768 ||
        utf8.encode(raw).length > 32768) {
      invalidHomeAssistantData();
    }
    // Bound nesting before jsonDecode, whose recursion limit isn't an app limit.
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final c in raw.codeUnits) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == 92) {
          escaped = true;
        } else if (c == 34) {
          quoted = false;
        }
      } else if (c == 34) {
        quoted = true;
      } else if (c == 123 || c == 91) {
        if (++depth > 16) invalidHomeAssistantData();
      } else if (c == 125 || c == 93) {
        depth--;
      }
    }
    Object? value;
    try {
      value = jsonDecode(raw);
    } catch (_) {
      invalidHomeAssistantData();
    }
    if (value is! Map<String, dynamic>) invalidHomeAssistantData();
    return value;
  }

  Future<Object?> _request(String type, int generation,
      {String? datasetId}) async {
    _check(generation);
    final socket = _socket;
    if (socket == null) {
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
    }
    final id = ++_id;
    socket.add(jsonEncode({
      'id': id,
      'type': type,
      if (datasetId != null) 'dataset_id': datasetId
    }));
    final response = await _next(generation);
    if (response['type'] != 'result' ||
        response['id'] != id ||
        response['success'] is! bool) {
      invalidHomeAssistantData();
    }
    if (response['success'] == true) return response['result'];
    final error = response['error'];
    final code = error is Map ? error['code'] : null;
    throw HomeAssistantCredentialException(switch (code) {
      'unauthorized' => HomeAssistantFailure.adminRequired,
      'unknown_command' => HomeAssistantFailure.threadUnavailable,
      'not_found' => HomeAssistantFailure.networkNotFound,
      _ => HomeAssistantFailure.connectionFailed,
    });
  }
}

Uri homeAssistantEndpoint(String input, {required bool allowUnencrypted}) {
  Uri? uri;
  try {
    uri = Uri.parse(input);
  } catch (_) {/* Fixed error below. */}
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !['', '/'].contains(uri.path) ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.host.contains('%') ||
      input.length > 2048) {
    throw const HomeAssistantCredentialException(
        HomeAssistantFailure.invalidUrl);
  }
  if (uri.scheme == 'http' && !allowUnencrypted) {
    throw const HomeAssistantCredentialException(
        HomeAssistantFailure.unencryptedConsentRequired);
  }
  return uri.replace(path: '/api/websocket');
}

bool isPrivateHomeAssistantAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 4) {
    return b[0] == 127 ||
        b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
  if (b.length != 16) return false;
  if (b.take(10).every((x) => x == 0) && b[10] == 255 && b[11] == 255) {
    return isPrivateHomeAssistantAddress(
        InternetAddress.fromRawAddress(b.sublist(12)));
  }
  return (b[0] & 254) == 252 || (b.take(15).every((x) => x == 0) && b[15] == 1);
}

/// WebSocket.connect uses openUrl for its handshake. This adapter refuses all
/// other requests and disables redirects before the handshake is sent.
class _FixedOriginClient implements HttpClient {
  _FixedOriginClient(
      this.origin, this.check, this.lookup, SecurityContext? context) {
    _inner.findProxy = (_) => 'DIRECT';
    _inner.connectionTimeout = const Duration(seconds: 10);
    _inner.connectionFactory = (uri, proxyHost, proxyPort) async {
      _verify(uri);
      check();
      final addresses = await lookup(uri.host);
      check();
      if (addresses.isEmpty) {
        throw const HomeAssistantCredentialException(
            HomeAssistantFailure.connectionFailed);
      }
      if (uri.scheme == 'http' &&
          !addresses.every(isPrivateHomeAssistantAddress)) {
        throw const HomeAssistantCredentialException(
            HomeAssistantFailure.publicHttpRefused);
      }
      // A custom connection factory must provide TLS itself. Retain the
      // numeric TCP transport across the entire TLS handshake so both TCP and
      // stalled TLS can be cancelled without a second DNS lookup.
      final ConnectionTask<Socket> task = uri.scheme == 'https'
          ? await startPinnedHomeAssistantTls(
              addresses.first, uri.port, uri.host, context)
          : await Socket.startConnect(addresses.first, uri.port);
      // Attach the completion/error owner before any cancellation race.
      task.socket.then((socket) {
        if (_closed) {
          socket.destroy();
        } else {
          _sockets.add(socket);
        }
      }, onError: (Object _) {});
      _tasks.add(task);
      if (_closed) {
        task.cancel();
        throw const HomeAssistantCredentialException(
            HomeAssistantFailure.cancelled);
      }
      return task;
    };
  }
  final Future<List<InternetAddress>> Function(String) lookup;
  final Uri origin;
  final void Function() check;
  final HttpClient _inner = HttpClient();
  final _tasks = <ConnectionTask<Socket>>[];
  final _sockets = <Socket>[];
  bool _closed = false;
  void _verify(Uri uri) {
    if (_closed ||
        uri.scheme != origin.scheme ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.path != origin.path ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
    }
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    _verify(url);
    if (method != 'GET') {
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
    }
    final request = await _inner.openUrl(method, url);
    check();
    request.followRedirects = false;
    return _UpgradeRequest(request);
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    for (final task in _tasks) {
      task.cancel();
    }
    for (final socket in _sockets) {
      socket.destroy();
    }
    _inner.close(force: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
}

// Dart bounds individual frames. Cap fragmented messages before its WebSocket
// parser aggregates them. Wrapping happens after HTTPS and HTTP upgrade, so TLS
// verification and HTTP parsing still operate on the original platform socket.
class _UpgradeRequest implements HttpClientRequest {
  _UpgradeRequest(this.inner);
  final HttpClientRequest inner;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  Future<HttpClientResponse> close() async =>
      _UpgradeResponse(await inner.close());
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
}

class _UpgradeResponse implements HttpClientResponse {
  _UpgradeResponse(this.inner);
  final HttpClientResponse inner;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  int get statusCode => inner.statusCode;
  @override
  Future<Socket> detachSocket() async =>
      _MessageBoundedSocket(await inner.detachSocket());
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
}

class _FrameBudget {
  final _header = <int>[];
  int _headerBytes = 2;
  int _remaining = 0;
  int _messageBytes = 0;
  void add(Uint8List bytes) {
    var offset = 0;
    while (offset < bytes.length) {
      if (_remaining > 0) {
        final available = bytes.length - offset;
        final skip = available < _remaining ? available : _remaining;
        offset += skip;
        _remaining -= skip;
        continue;
      }
      _header.add(bytes[offset++]);
      if (_header.length == 2) {
        final length = _header[1] & 127;
        _headerBytes = length == 126 ? 4 : (length == 127 ? 10 : 2);
      }
      if (_header.length < _headerBytes) continue;
      final opcode = _header[0] & 15;
      if ((_header[0] & 112) != 0 || (_header[1] & 128) != 0) {
        throw const WebSocketException('Unsupported frame');
      }
      var size = _header[1] & 127;
      if (size >= 126) {
        size = 0;
        for (var i = 2; i < _headerBytes; i++) {
          size = size * 256 + _header[i];
          if (size > 32768) {
            throw const WebSocketException('Message size exceeded');
          }
        }
      }
      if (opcode < 8) {
        _messageBytes += size;
        if (_messageBytes > 32768) {
          throw const WebSocketException('Message size exceeded');
        }
        if ((_header[0] & 128) != 0) _messageBytes = 0;
      } else if (size > 125) {
        throw const WebSocketException('Control frame size exceeded');
      }
      _remaining = size;
      _header.clear();
      _headerBytes = 2;
    }
  }
}

class _MessageBoundedSocket extends Stream<Uint8List> implements Socket {
  _MessageBoundedSocket(this.inner) {
    final budget = _FrameBudget();
    _stream =
        inner.transform(StreamTransformer<Uint8List, Uint8List>.fromHandlers(
      handleData: (data, sink) {
        try {
          budget.add(data);
          sink.add(data);
        } catch (_) {
          sink.addError(
              const WebSocketException('Message size or frame rejected'));
          sink.close();
          inner.destroy();
        }
      },
    ));
  }
  final Socket inner;
  late final Stream<Uint8List> _stream;
  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  void add(List<int> data) => inner.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => inner.addStream(stream);
  @override
  Future<void> flush() => inner.flush();
  @override
  Future<dynamic> close() => inner.close();
  @override
  Future<dynamic> get done => inner.done;
  @override
  Encoding get encoding => inner.encoding;
  @override
  set encoding(Encoding value) {
    inner.encoding = value;
  }

  @override
  void write(Object? object) => inner.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      inner.writeAll(objects, separator);
  @override
  void writeln([Object? object = '']) => inner.writeln(object);
  @override
  void writeCharCode(int charCode) => inner.writeCharCode(charCode);
  @override
  void destroy() => inner.destroy();
  @override
  bool setOption(SocketOption option, bool enabled) =>
      inner.setOption(option, enabled);
  @override
  InternetAddress get address => inner.address;
  @override
  InternetAddress get remoteAddress => inner.remoteAddress;
  @override
  int get port => inner.port;
  @override
  int get remotePort => inner.remotePort;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const HomeAssistantCredentialException(
          HomeAssistantFailure.connectionFailed);
}
