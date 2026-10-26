import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Own the raw TCP socket across TLS negotiation. SecureSocket.startConnect's
/// task cancellation does not close an already-connected, stalled TLS handshake.
Future<ConnectionTask<Socket>> startPinnedHomeAssistantTls(
    InternetAddress address,
    int port,
    String hostname,
    SecurityContext? context) async {
  final tcp = await RawSocket.startConnect(address, port);
  RawSocket? transport;
  var cancelled = false;
  final secure = tcp.socket.then<Socket>((raw) async {
    transport = raw;
    if (cancelled) {
      raw.close();
      throw const SocketException('Connection cancelled');
    }
    try {
      // secure() uses the explicit original hostname for SNI and certificate
      // checks; it never resolves that hostname. Null context means OS trust.
      final tls =
          await RawSecureSocket.secure(raw, host: hostname, context: context);
      if (cancelled) {
        raw.close();
        tls.close();
        throw const SocketException('Connection cancelled');
      }
      return _TlsSocket(tls, () {
        raw.close();
      });
    } catch (_) {
      raw.close();
      rethrow;
    }
  });
  return ConnectionTask.fromSocket(secure, () {
    cancelled = true;
    tcp.cancel();
    transport?.close();
  });
}

/// Public RawSecureSocket → Socket adapter for HttpClient. One bounded write
/// chunk is retained while waiting for writable events; inbound pause/resume
/// directly controls the secure socket's read events.
class _TlsSocket extends Stream<Uint8List> implements Socket {
  _TlsSocket(this.raw, this.abortTransport) {
    _reads = StreamController<Uint8List>(
        sync: true,
        onListen: () {
          raw.readEventsEnabled = true;
        },
        onPause: () {
          raw.readEventsEnabled = false;
        },
        onResume: () {
          raw.readEventsEnabled = true;
        },
        onCancel: destroy);
    raw.readEventsEnabled = false;
    raw.writeEventsEnabled = false;
    _sink = IOSink(_TlsWriter(this));
    raw.listen((event) {
      if (event == RawSocketEvent.read) {
        final data = raw.read(32768);
        if (data != null && !_reads.isClosed) _reads.add(data);
      } else if (event == RawSocketEvent.write) {
        raw.writeEventsEnabled = false;
        final ready = _writable;
        _writable = null;
        ready?.complete();
      } else if (event == RawSocketEvent.readClosed ||
          event == RawSocketEvent.closed) {
        destroy();
      }
    }, onError: (Object _) {
      if (!_reads.isClosed) {
        _reads.addError(const SocketException('TLS connection failed'));
      }
      destroy();
    }, onDone: destroy);
  }
  final RawSecureSocket raw;
  final void Function() abortTransport;
  late final StreamController<Uint8List> _reads;
  late final IOSink _sink;
  Completer<void>? _writable;
  bool _destroyed = false;

  Future<void> _write(List<int> bytes) async {
    var offset = 0;
    while (offset < bytes.length) {
      if (_destroyed) throw const SocketException('TLS connection closed');
      offset += raw.write(bytes, offset, bytes.length - offset);
      if (offset < bytes.length) {
        final ready = Completer<void>();
        _writable = ready;
        raw.writeEventsEnabled = true;
        await ready.future;
      }
    }
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    abortTransport();
    raw.close();
    final ready = _writable;
    _writable = null;
    ready?.complete();
    if (!_reads.isClosed) _reads.close();
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _reads.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> flush() => _sink.flush();
  @override
  Future<dynamic> close() => _sink.close();
  @override
  Future<dynamic> get done => _sink.done;
  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) {
    _sink.encoding = value;
  }

  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  bool setOption(SocketOption option, bool enabled) =>
      raw.setOption(option, enabled);
  @override
  InternetAddress get address => raw.address;
  @override
  InternetAddress get remoteAddress => raw.remoteAddress;
  @override
  int get port => raw.port;
  @override
  int get remotePort => raw.remotePort;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const SocketException('Unsupported socket operation');
}

class _TlsWriter implements StreamConsumer<List<int>> {
  _TlsWriter(this.socket);
  final _TlsSocket socket;
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      await socket._write(bytes);
    }
  }

  @override
  Future<void> close() async {
    socket.raw.shutdown(SocketDirection.send);
  }
}
