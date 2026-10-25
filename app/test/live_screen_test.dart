import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thread_network_tool/live_api.dart';
import 'package:thread_network_tool/live_screen.dart';
import 'package:thread_network_tool/main.dart';

Map<String, Object?> fixture({
  bool credentials = true,
  String? probeStatus,
  Object authenticated = 'unknown',
  String? identityMatch,
}) =>
    {
      'schema_version': 1,
      'mode': 'live',
      'credential_available': credentials,
      'credential_network_name': credentials ? 'PrivateMesh' : null,
      'discovery_status': 'completed',
      'observed_at': '2026-10-25T10:00:00Z',
      'routers': [
        {
          'id': 'device-secret-id',
          'service_name': 'Living room router',
          'network_name': 'PrivateMesh',
          'thread_version': '1.3',
          'endpoint_usable': true,
          'probe': probeStatus == null
              ? null
              : {
                  'probe_status': probeStatus,
                  'authenticated': authenticated,
                  'identity_match': identityMatch,
                  'active_status':
                      probeStatus == 'completed' || probeStatus == 'partial'
                          ? 'read'
                          : 'unknown',
                  'pending_status':
                      probeStatus == 'completed' || probeStatus == 'partial'
                          ? 'empty'
                          : 'unknown',
                  'checked_at': '2026-10-25T10:01:00Z',
                },
        },
      ],
    };

class FixtureApi implements LiveApi {
  FixtureApi(this.current);
  LiveState current;
  Future<LiveState> Function()? onProbe;
  Future<LiveState> Function(String)? onCredentials;
  int probeCalls = 0;
  int credentialCalls = 0;

  @override
  Future<LiveState> state() async => current;
  @override
  Future<LiveState> discover() async => current;
  @override
  Future<LiveState> credentials(String dataset) async {
    credentialCalls++;
    return onCredentials == null ? current : onCredentials!(dataset);
  }

  @override
  Future<LiveState> probe(String routerId) async {
    probeCalls++;
    return onProbe == null ? current : onProbe!();
  }
}

class CapabilityFixtureApi extends FixtureApi implements NetworkMoveApi {
  CapabilityFixtureApi(super.current);

  @override
  Future<LiveState> credentialsForRole(String role, String dataset) async =>
      current;
  @override
  Future<LiveState> probeForRole(String role, String routerId) async => current;
  @override
  Future<NetworkMovePlan> networkMovePlan(
          {required String targetRouterId,
          required EmptySourceAttestationInput attestation,
          required int delaySeconds}) =>
      throw StateError('No plan requested');
  @override
  Future<NetworkMovePlan?> currentNetworkMovePlan() async => null;
}

void main() {
  test('live route requires an exact lowercase fragment token', () {
    expect(liveSessionFromFragment('session=${'a' * 64}'), 'a' * 64);
    expect(liveSessionFromFragment('view=live&session=${'a' * 64}'), 'a' * 64);
    expect(liveSessionFromFragment('session=${'A' * 64}'), isNull);
    expect(liveSessionFromFragment('session=${'a' * 63}'), isNull);
    expect(liveSessionFromFragment('session=${'a' * 64}extra'), isNull);
  });

  test('HTTP API uses same origin and bearer token for read actions', () async {
    final requests = <http.Request>[];
    final api = HttpLiveApi(
      session: 'a' * 64,
      baseUri: Uri.parse('http://127.0.0.1:5188/index.html#session=ignored'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(fixture()), 200);
      }),
    );
    await api.state();
    await api.discover();
    await api.credentials('SECRET-DATASET');
    await api.probe('device-secret-id');
    expect(requests.map((r) => r.url.path),
        ['/api/state', '/api/discover', '/api/credentials', '/api/probe']);
    expect(requests.map((r) => r.method), ['GET', 'POST', 'POST', 'POST']);
    expect(
        requests.every((r) =>
            r.headers['Authorization'] == 'Bearer ${'a' * 64}' &&
            r.url.origin == 'http://127.0.0.1:5188'),
        isTrue);
    expect(jsonDecode(requests[2].body), {'dataset': 'SECRET-DATASET'});
    expect(jsonDecode(requests[3].body), {'router_id': 'device-secret-id'});
  });

  test('HTTP failure returns generic exception without server body', () async {
    final api = HttpLiveApi(
      session: 'a' * 64,
      baseUri: Uri.parse('http://127.0.0.1:5188/'),
      client:
          MockClient((_) async => http.Response('SECRET server detail', 409)),
    );
    expect(api.discover(), throwsA(isA<LiveApiException>()));
  });

  test('state parser rejects malformed status and duplicate opaque IDs', () {
    final bad = fixture();
    bad['discovery_status'] = 'secret\nstate';
    expect(() => LiveState.fromJson(bad), throwsFormatException);
    final duplicate = fixture();
    (duplicate['routers'] as List)
        .add(Map<String, Object?>.from((duplicate['routers'] as List).first));
    expect(() => LiveState.fromJson(duplicate), throwsFormatException);
    for (final field in ['probe_status', 'active_status', 'pending_status']) {
      final corrupt = fixture(
          probeStatus: 'completed',
          authenticated: true,
          identityMatch: 'match');
      ((corrupt['routers'] as List).first['probe'] as Map)[field] = 'unsafe';
      expect(() => LiveState.fromJson(corrupt), throwsFormatException);
    }
  });

  test('report excludes identifiers, names, addresses and secret-like values',
      () {
    final state = LiveState.fromJson(fixture(
        probeStatus: 'completed', authenticated: true, identityMatch: 'match'));
    final report = liveReport(state);
    expect(report, contains('Authenticated identity matches: 1'));
    for (final private in [
      'PrivateMesh',
      'device-secret-id',
      'Living room router',
      '127.0.0.1'
    ]) {
      expect(report, isNot(contains(private)));
    }
  });

  test('report counts role-bound reads separately without household data', () {
    final data = fixture(credentials: false);
    data['source_credential_available'] = true;
    data['source_credential_network_name'] = 'SourceMesh';
    data['target_credential_available'] = true;
    data['target_credential_network_name'] = 'TargetMesh';
    ((data['routers'] as List).single as Map)['role_probes'] = {
      'source': {
        'probe_status': 'completed',
        'authenticated': true,
        'identity_match': 'match',
        'active_status': 'read',
        'pending_status': 'empty',
        'checked_at': '2026-10-25T10:01:00Z',
      },
      'target': {
        'probe_status': 'completed',
        'authenticated': true,
        'identity_match': 'mismatch',
        'active_status': 'read',
        'pending_status': 'empty',
        'checked_at': '2026-10-25T10:02:00Z',
      },
    };
    final report = liveReport(LiveState.fromJson(data));
    expect(report, contains('Inspection credentials available: no'));
    expect(report, contains('Router reads attempted: 0'));
    expect(report, contains('Source credentials available: yes'));
    expect(report, contains('Source router reads attempted: 1'));
    expect(report, contains('Source authenticated identity matches: 1'));
    expect(report, contains('Target credentials available: yes'));
    expect(report, contains('Target router reads attempted: 1'));
    expect(report, contains('Target authenticated identity matches: 0'));
    for (final private in [
      'PrivateMesh',
      'SourceMesh',
      'TargetMesh',
      'device-secret-id',
      'Living room router',
    ]) {
      expect(report, isNot(contains(private)));
    }
  });

  test('partial matching read is not verified or counted', () {
    final state = LiveState.fromJson(fixture(
        probeStatus: 'partial', authenticated: true, identityMatch: 'match'));
    expect(state.routers.single.probe!.verified, isFalse);
    expect(liveReport(state), contains('Authenticated identity matches: 0'));
  });

  Future<void> pumpLive(WidgetTester tester, FixtureApi api,
      {Size size = const Size(1000, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ThreadNetworkApp(liveApi: api));
    await tester.pumpAndSettle();
  }

  testWidgets('live screen distinguishes verified and mismatch',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture()));
    await pumpLive(tester, api);
    expect(find.byKey(const Key('live-banner')), findsOneWidget);
    expect(find.textContaining('unverified'), findsWidgets);
    expect(find.text('Not checked'), findsOneWidget);
    api.onProbe = () async => LiveState.fromJson(fixture(
        probeStatus: 'completed', authenticated: true, identityMatch: 'match'));
    await tester.tap(find.byKey(const Key('live-read-0')));
    await tester.pumpAndSettle();
    expect(find.text('Verified · network matches'), findsOneWidget);
    api.onProbe = () async => LiveState.fromJson(fixture(
        probeStatus: 'completed',
        authenticated: true,
        identityMatch: 'mismatch'));
    await tester.tap(find.byKey(const Key('live-read-0')));
    await tester.pumpAndSettle();
    expect(find.text('Different network'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('live-join-disabled')))
            .onPressed,
        isNull);
  });

  testWidgets('network-move entry appears only for a capable live adapter',
      (tester) async {
    await pumpLive(tester, FixtureApi(LiveState.fromJson(fixture())));
    expect(find.byKey(const Key('live-network-move')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpLive(tester, CapabilityFixtureApi(LiveState.fromJson(fixture())));
    expect(find.byKey(const Key('live-network-move')), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-network-move')));
    await tester.pumpAndSettle();
    expect(find.text('Network move review'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('move-dispatch-disabled')), 250);
    expect(find.byKey(const Key('move-dispatch-disabled')), findsOneWidget);
  });

  testWidgets('timeout, request failure and missing credentials remain safe',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(credentials: false)));
    await pumpLive(tester, api);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('live-read-0')))
            .onPressed,
        isNull);
    api.current = LiveState.fromJson(
        fixture(probeStatus: 'timeout', authenticated: 'unknown'));
    await tester.tap(find.byKey(const Key('live-discover')));
    await tester.pumpAndSettle();
    expect(find.text('Check timed out'), findsOneWidget);
    api.current = LiveState.fromJson(fixture(probeStatus: 'error'));
    await tester.tap(find.byKey(const Key('live-discover')));
    await tester.pumpAndSettle();
    expect(find.text('Check failed'), findsOneWidget);
    api.onProbe = () async => throw const LiveApiException();
    api.current = LiveState.fromJson(fixture());
    await tester.tap(find.byKey(const Key('live-discover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-read-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-error')), findsOneWidget);
    expect(api.probeCalls, 1);
  });

  testWidgets('guided eero route explains copied dataset and imports it',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(credentials: false)));
    api.onCredentials = (_) async => LiveState.fromJson(fixture());
    await pumpLive(tester, api);
    await tester.tap(find.byKey(const Key('live-import')));
    await tester.pumpAndSettle();
    expect(find.text('Set up network access'), findsWidgets);
    expect(find.byKey(const Key('live-dataset-input')), findsNothing);
    await tester.tap(find.byKey(const Key('live-eero-route')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Active operational dataset'), findsWidgets);
    expect(find.textContaining('Thread Network Key'), findsWidgets);
    final input =
        tester.widget<TextField>(find.byKey(const Key('live-dataset-input')));
    expect(input.obscureText, isTrue);
    await tester.enterText(find.byKey(const Key('live-dataset-input')), 'AABB');
    await tester.tap(find.byKey(const Key('live-import-submit')));
    await tester.pumpAndSettle();
    expect(api.credentialCalls, 1);
    expect(find.textContaining('Credentials ready'), findsOneWidget);
  });

  testWidgets('advanced route remains explicit', (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(credentials: false)));
    await pumpLive(tester, api);
    await tester.tap(find.byKey(const Key('live-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-advanced-route')));
    await tester.pumpAndSettle();
    expect(find.textContaining('hex'), findsWidgets);
    expect(find.byKey(const Key('live-dataset-input')), findsOneWidget);
  });

  testWidgets('malformed and server failure clear masked input without echo',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(credentials: false)));
    api.onCredentials = (_) async => throw const LiveApiException();
    await pumpLive(tester, api);
    await tester.tap(find.byKey(const Key('live-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-eero-route')));
    await tester.pumpAndSettle();
    const secret = 'DEADBEEFDEADBEEF';
    await tester.enterText(find.byKey(const Key('live-dataset-input')), 'bad');
    await tester.tap(find.byKey(const Key('live-import-submit')));
    await tester.pumpAndSettle();
    expect(api.credentialCalls, 0);
    expect(find.byKey(const Key('live-import-error')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('live-dataset-input')), secret);
    await tester.tap(find.byKey(const Key('live-import-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-import-error')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('live-dataset-input')))
            .controller!
            .text,
        isEmpty);
    expect(find.text(secret), findsNothing);
    expect(api.credentialCalls, 1);
  });

  testWidgets('cancel clears draft and Check stays disabled without access',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(credentials: false)));
    await pumpLive(tester, api);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('live-read-0')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('live-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-eero-route')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('live-dataset-input')), 'AABB');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-eero-route')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('live-dataset-input')))
            .controller!
            .text,
        isEmpty);
    expect(api.credentialCalls, 0);
  });

  testWidgets('initial idle search does not claim no routers found',
      (tester) async {
    final idle = fixture(credentials: false)
      ..['discovery_status'] = 'idle'
      ..['observed_at'] = null
      ..['routers'] = [];
    await pumpLive(tester, FixtureApi(LiveState.fromJson(idle)));
    expect(find.textContaining('No routers found'), findsNothing);
    expect(find.textContaining('Find routers'), findsWidgets);
  });

  testWidgets('guided dialog fits narrow screen with enlarged text',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(credentials: false)));
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: ThreadNetworkApp(liveApi: api),
    ));
    await tester.pumpAndSettle();
    final accessButton = find.byKey(const Key('live-import'));
    await tester.scrollUntilVisible(accessButton, 200);
    await tester.ensureVisible(accessButton);
    await tester.pumpAndSettle();
    final accessButtonRect = tester.getRect(accessButton);
    expect(accessButtonRect.top, greaterThanOrEqualTo(0));
    expect(accessButtonRect.bottom, lessThanOrEqualTo(640));
    await tester.tap(accessButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Set up network access'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('live-eero-route')));
    await tester.tap(find.byKey(const Key('live-eero-route')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('live-dataset-input')));
    expect(find.byKey(const Key('live-dataset-input')), findsOneWidget);
    expect(find.byKey(const Key('live-import-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact viewport keeps read, join and report accessible',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture()));
    await pumpLive(tester, api, size: const Size(320, 640));
    await tester.scrollUntilVisible(find.byKey(const Key('live-read-0')), 250);
    expect(find.byKey(const Key('live-read-0')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('live-join-disabled')), 250);
    expect(find.byKey(const Key('live-join-disabled')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('live-report')), -250);
    await tester.tap(find.byKey(const Key('live-report')));
    await tester.pumpAndSettle();
    final report = tester
        .widget<SelectableText>(find.byKey(const Key('live-report-text')))
        .data!;
    expect(report, isNot(contains('PrivateMesh')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('technical details stay collapsed until requested',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(
        probeStatus: 'partial', authenticated: true, identityMatch: 'match')));
    await pumpLive(tester, api);
    expect(find.text('Check incomplete'), findsOneWidget);
    expect(find.textContaining('Authenticated read completed'), findsNothing);
    expect(find.textContaining('Thread version:'), findsNothing);
    expect(find.textContaining('2026-10-25T10:01:00'), findsNothing);
    await tester.tap(find.byKey(const Key('live-details-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-full-name-0')), findsOneWidget);
    expect(find.textContaining('Authentication succeeded'), findsOneWidget);
    expect(find.textContaining('Thread version:'), findsOneWidget);
    expect(find.textContaining('2026-10-25T10:01:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-how-it-works')));
    await tester.pumpAndSettle();
    expect(find.textContaining('advertisements only suggest'), findsOneWidget);
  });

  testWidgets('long router name fits narrow screen and enlarged text',
      (tester) async {
    final data = fixture();
    ((data['routers'] as List).single as Map)['service_name'] =
        'A very long border router name that should not hide the check action';
    final api = FixtureApi(LiveState.fromJson(data));
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: ThreadNetworkApp(liveApi: api),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('live-read-0')), 200);
    expect(find.byKey(const Key('live-read-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
