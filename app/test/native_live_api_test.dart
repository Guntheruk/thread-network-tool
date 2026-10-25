import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/live_api.dart';
import 'package:thread_network_tool/main.dart';
import 'package:thread_network_tool/native/session.dart';
import 'package:thread_network_tool/native_live_api.dart';

void main() {
  test('direct adapter discovers, imports, and verifies one router', () async {
    final calls = <String>[];
    final api = NativeLiveApi(native: (arguments, credential) async {
      calls.add(arguments.first);
      switch (arguments.first) {
        case 'discover':
          expect(credential, isNull);
          return const NativeReply(0, {
            'schema_version': 1,
            'discovery_status': 'completed',
            'routers': [
              {
                'service_name': 'Test router',
                'address': '192.168.1.42',
                'port': 49191,
                'network_name': 'TestMesh',
                'thread_version': '1.3',
              },
            ],
          });
        case 'inspect':
          expect(credential, 'AABBCCDD');
          return const NativeReply(0, {
            'schema_version': 1,
            'valid': true,
            'network_name': 'TestMesh',
          });
        case 'probe':
          expect(arguments, ['probe', '192.168.1.42', '49191']);
          expect(credential, 'AABBCCDD');
          return const NativeReply(0, {
            'schema_version': 1,
            'probe_status': 'completed',
            'authenticated': true,
            'identity_match': 'match',
            'active_status': 'read',
            'pending_status': 'empty',
          });
      }
      fail('Unexpected native operation');
    });

    final initial = await api.state();
    expect(initial.discoveryStatus, 'idle');
    final discovered = await api.discover();
    expect(discovered.routers.single.endpointUsable, isTrue);
    expect(discovered.routers.single.probe, isNull);
    final imported = await api.credentials('AABBCCDD');
    expect(imported.credentialAvailable, isTrue);
    final read = await api.probe(imported.routers.single.id);
    expect(read.routers.single.probe!.verified, isTrue);
    expect(calls, ['discover', 'inspect', 'probe']);
  });

  test('unsupported adapter exposes state without native operations', () async {
    const api = UnsupportedLiveApi();
    expect((await api.state()).discoveryStatus, 'unsupported');
    expect((await api.discover()).routers, isEmpty);
    expect(api.credentials('AABBCCDD'), throwsA(isA<LiveApiException>()));
    expect(api.probe('opaque'), throwsA(isA<LiveApiException>()));
  });

  testWidgets('injected native API uses live screen, not demo', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const ThreadNetworkApp(liveApi: UnsupportedLiveApi()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-banner')), findsOneWidget);
    expect(find.textContaining('Live discovery is unavailable'), findsOneWidget);
    expect(find.byKey(const Key('synthetic-demo-banner')), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('live-import')))
            .onPressed,
        isNull);
  });
}
