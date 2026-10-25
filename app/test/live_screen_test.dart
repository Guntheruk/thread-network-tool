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

  @override
  Future<LiveState> state() async => current;
  @override
  Future<LiveState> discover() async => current;
  @override
  Future<LiveState> credentials(String dataset) async =>
      onCredentials == null ? current : onCredentials!(dataset);
  @override
  Future<LiveState> probe(String routerId) async {
    probeCalls++;
    return onProbe == null ? current : onProbe!();
  }
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
    await tester.pumpWidget(MaterialApp(home: LiveScreen(api: api)));
    await tester.pumpAndSettle();
  }

  testWidgets('live screen distinguishes verified and mismatch',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture()));
    await pumpLive(tester, api);
    expect(find.byKey(const Key('live-banner')), findsOneWidget);
    expect(find.textContaining('unverified'), findsWidgets);
    expect(find.text('No authenticated read yet'), findsOneWidget);
    api.onProbe = () async => LiveState.fromJson(fixture(
        probeStatus: 'completed', authenticated: true, identityMatch: 'match'));
    await tester.tap(find.byKey(const Key('live-read-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('imported network identity matches'),
        findsOneWidget);
    api.onProbe = () async => LiveState.fromJson(fixture(
        probeStatus: 'completed',
        authenticated: true,
        identityMatch: 'mismatch'));
    await tester.tap(find.byKey(const Key('live-read-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Identity mismatch'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('live-join-disabled')))
            .onPressed,
        isNull);
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
    expect(find.textContaining('Read timed out'), findsOneWidget);
    api.onProbe = () async => throw const LiveApiException();
    api.current = LiveState.fromJson(fixture());
    await tester.tap(find.byKey(const Key('live-discover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-read-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-error')), findsOneWidget);
    expect(api.probeCalls, 1);
  });

  testWidgets('credential failure clears masked entry without echo',
      (tester) async {
    final api = FixtureApi(LiveState.fromJson(fixture(credentials: false)));
    api.onCredentials = (_) async => throw const LiveApiException();
    await pumpLive(tester, api);
    await tester.tap(find.byKey(const Key('live-import')));
    await tester.pumpAndSettle();
    const secret = 'DEADBEEFDEADBEEF';
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
}
