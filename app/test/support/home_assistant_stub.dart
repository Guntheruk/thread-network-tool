import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String dataset(String name, String xpan, int channel) =>
    '00030000${channel.toRadixString(16).padLeft(2, '0')}0208$xpan'
    '03${utf8.encode(name).length.toRadixString(16).padLeft(2, '0')}'
    '${utf8.encode(name).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'
    '010212340510000102030405060708090a0b0c0d0e0f'
    '0410101112131415161718191a1b1c1d1e1f0e080000000000010000';

const rows = [
  {
    'dataset_id': 'first',
    'network_name': 'LabOne',
    'extended_pan_id': '0011223344556677',
    'channel': 15,
    'pan_id': '1234',
    'preferred': true
  },
  {
    'dataset_id': 'second',
    'network_name': 'LabTwo',
    'extended_pan_id': '8899aabbccddeeff',
    'channel': 20,
    'pan_id': '1234',
    'preferred': false
  },
];
const token = 'SYNTHETIC_TOKEN_DO_NOT_LOG';

class HaStub {
  HaStub(this.server);
  final HttpServer server;
  final commands = <Map<String, dynamic>>[];
  final sockets = <WebSocket>[];
  bool authenticated = false;
  String get url => 'http://127.0.0.1:${server.port}';
  static Future<HaStub> start({
    FutureOr<void> Function(HaStub, WebSocket, Map<String, dynamic>)? handler,
    String greeting = '{"type":"auth_required","ha_version":"test"}',
    bool greet = true,
    SecurityContext? securityContext,
  }) async {
    final stub = HaStub(securityContext == null
        ? await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        : await HttpServer.bindSecure(
            InternetAddress.loopbackIPv4, 0, securityContext));
    stub.server.listen((request) async {
      expect(request.uri.path, '/api/websocket');
      expect(request.uri.query, isEmpty);
      expect(request.headers.value('authorization'), isNull);
      final ws = await WebSocketTransformer.upgrade(request);
      stub.sockets.add(ws);
      if (greet) ws.add(greeting);
      ws.listen((raw) async {
        final message = jsonDecode(raw as String) as Map<String, dynamic>;
        stub.commands.add(message);
        if (handler != null) {
          await handler(stub, ws, message);
        } else {
          stub.reply(ws, message);
        }
      }, onError: (_) {});
    }, onError: (_) {});
    return stub;
  }

  void reply(WebSocket ws, Map<String, dynamic> message) {
    if (message['type'] == 'auth') {
      authenticated = message['access_token'] == token;
      ws.add(jsonEncode({'type': authenticated ? 'auth_ok' : 'auth_invalid'}));
    } else if (message['type'] == 'thread/list_datasets') {
      expect(authenticated, true);
      result(ws, message, {'datasets': rows});
    } else if (message['type'] == 'thread/get_dataset_tlv') {
      expect(authenticated, true);
      expect(message['dataset_id'], 'second');
      result(ws, message, {'tlv': dataset('LabTwo', '8899aabbccddeeff', 20)});
    } else {
      fail('Unexpected command type');
    }
  }

  void result(WebSocket ws, Map<String, dynamic> request, Object? payload) {
    ws.add(jsonEncode({
      'id': request['id'],
      'type': 'result',
      'success': true,
      'result': payload
    }));
  }

  Future<void> close() async {
    for (final ws in sockets) {
      await ws.close();
    }
    await server.close(force: true);
  }
}
