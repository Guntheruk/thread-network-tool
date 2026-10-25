import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/live_api.dart';
import 'package:thread_network_tool/move/network_move_plan.dart';
import 'package:thread_network_tool/network_move_screen.dart';

Map<String, Object?> _stateJson({bool source = false, bool target = false}) => {
      'schema_version': 1,
      'mode': 'live',
      'credential_available': false,
      'credential_network_name': null,
      'source_credential_available': source,
      'source_credential_network_name': source ? 'SourceMesh' : null,
      'target_credential_available': target,
      'target_credential_network_name': target ? 'TargetMesh' : null,
      'discovery_status': 'completed',
      'observed_at': '2026-10-25T10:00:00Z',
      'routers': [
        {
          'id': 'target-id',
          'service_name': 'Target border router',
          'network_name': 'TargetMesh',
          'thread_version': '1.3',
          'endpoint_usable': true,
          'probe': null,
          'role_probes': <String, dynamic>{},
        },
        {
          'id': 'source-a',
          'service_name': 'Source router one',
          'network_name': 'SourceMesh',
          'thread_version': '1.3',
          'endpoint_usable': true,
          'probe': null,
          'role_probes': <String, dynamic>{},
        },
        {
          'id': 'source-b',
          'service_name': 'Source router two',
          'network_name': 'SourceMesh',
          'thread_version': '1.3',
          'endpoint_usable': true,
          'probe': null,
          'role_probes': <String, dynamic>{},
        },
      ],
    };

NetworkMovePlan _plan({
  String decision = 'needs_evidence',
  DateTime? validUntil,
}) =>
    NetworkMovePlan.fromJson({
      'schema_version': 1,
      'mode': 'network_move_review',
      'decision': decision,
      'blockers': decision == 'needs_evidence'
          ? ['source_read_missing_or_stale']
          : <String>[],
      'review_id': 'review-id',
      'review_valid_until':
          (validUntil ?? DateTime.utc(2026, 10, 25, 10, 5)).toIso8601String(),
      'affected_scope': 'whole_source_network',
      'source_routers': [
        {
          'router_id': 'source-a',
          'service_name': 'Source router one',
          'read_checked_at': null,
          'read_status': 'not_checked',
        },
        {
          'router_id': 'source-b',
          'service_name': 'Source router two',
          'read_checked_at': null,
          'read_status': 'not_checked',
        },
      ],
      'target_router_id': 'target-id',
      'target_read_checked_at': null,
      'unknown_offline_devices': true,
      'inventory_complete': false,
      'delay_seconds': 300,
      'verification': 'Check source and target again after propagation.',
      'recovery': 'Manual recovery; rollback is not guaranteed.',
    });

class MoveFake implements NetworkMoveApi {
  LiveState current = LiveState.fromJson(_stateJson());
  final credentialRoles = <String>[];
  final probeRoles = <String>[];
  final probeRouters = <String>[];
  int planCalls = 0;
  String? plannedTarget;
  EmptySourceAttestationInput? attestation;
  int? delay;
  NetworkMovePlan? preparedPlan;

  @override
  Future<LiveState> state() async => current;
  @override
  Future<LiveState> discover() async => current;
  @override
  Future<LiveState> credentials(String dataset) =>
      throw StateError('Legacy credentials must not be used');
  @override
  Future<LiveState> probe(String routerId) =>
      throw StateError('Legacy probe must not be used');
  @override
  Future<LiveState> credentialsForRole(String role, String dataset) async {
    credentialRoles.add(role);
    current = LiveState.fromJson(_stateJson(
      source: role == 'source' || current.sourceCredentialAvailable,
      target: role == 'target' || current.targetCredentialAvailable,
    ));
    return current;
  }

  @override
  Future<LiveState> probeForRole(String role, String routerId) async {
    probeRoles.add(role);
    probeRouters.add(routerId);
    return current;
  }

  @override
  Future<NetworkMovePlan> networkMovePlan(
      {required String targetRouterId,
      required EmptySourceAttestationInput attestation,
      required int delaySeconds}) async {
    planCalls++;
    plannedTarget = targetRouterId;
    this.attestation = attestation;
    delay = delaySeconds;
    return preparedPlan ?? _plan();
  }

  @override
  Future<NetworkMovePlan?> currentNetworkMovePlan() async => null;
}

Future<void> _pump(WidgetTester tester, MoveFake api,
    {Size size = const Size(900, 900), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: NetworkMoveScreen(api: api, initialState: api.current),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _ensureVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 250);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await _ensureVisible(tester, key);
  final finder = find.byKey(key);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _ensureEndKeyVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  final scrollable =
      tester.state<ScrollableState>(find.byType(Scrollable).first);
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    final position = scrollable.position;
    if (position.pixels <= position.minScrollExtent) break;
    final step = position.viewportDimension / 2;
    position.jumpTo((position.pixels - step)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('attestation is off and plan never runs from selection alone',
      (tester) async {
    final api = MoveFake();
    await _pump(tester, api);
    await _ensureVisible(tester, const Key('move-empty-source-attestation'));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const Key('move-empty-source-attestation')))
            .value,
        false);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('move-prepare')))
            .onPressed,
        isNull);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _ensureVisible(tester, const Key('move-prepare'));
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('move-prepare')))
            .onPressed,
        isNull);
    expect(api.planCalls, 0);
    await _ensureEndKeyVisible(tester, const Key('move-dispatch-disabled'));
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('move-dispatch-disabled')))
            .onPressed,
        isNull);
  });

  testWidgets('access dialog cancel does not import either role',
      (tester) async {
    final api = MoveFake();
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-access'));
    await _tapVisible(tester, const Key('live-eero-route'));
    await tester.enterText(find.byKey(const Key('live-dataset-input')), 'AABB');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, const Key('move-source-access'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.credentialRoles, isEmpty);
    expect(api.planCalls, 0);
  });

  testWidgets('target and source setup and checks keep explicit roles',
      (tester) async {
    final api = MoveFake();
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-access'));
    await _tapVisible(tester, const Key('live-eero-route'));
    await tester.enterText(find.byKey(const Key('live-dataset-input')), 'AABB');
    await _tapVisible(tester, const Key('live-import-submit'));
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-check-target'));
    await _tapVisible(tester, const Key('move-source-access'));
    await _tapVisible(tester, const Key('live-eero-route'));
    await tester.enterText(find.byKey(const Key('live-dataset-input')), 'CCDD');
    await _tapVisible(tester, const Key('live-import-submit'));
    await _tapVisible(tester, const Key('move-check-source-source-a'));
    await _tapVisible(tester, const Key('move-check-source-source-b'));
    expect(api.credentialRoles, ['target', 'source']);
    expect(api.probeRoles, ['target', 'source', 'source']);
    expect(api.probeRouters, ['target-id', 'source-a', 'source-b']);
    expect(api.planCalls, 0);
  });

  testWidgets('explicit attestation prepares a read-only whole-network review',
      (tester) async {
    final api = MoveFake();
    await _pump(tester, api, size: const Size(320, 640), textScale: 2);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    expect(api.planCalls, 1);
    expect(api.plannedTarget, 'target-id');
    expect(api.attestation!.toJson()['scope'], 'whole_source_network');
    expect(api.delay, 300);
    await _ensureVisible(tester, const Key('move-review'));
    expect(find.text('Source router one'), findsWidgets);
    expect(find.text('Source router two'), findsWidgets);
    expect(find.textContaining('entire source Thread network'), findsWidgets);
    expect(find.textContaining('Offline or unobserved devices'), findsWidgets);
    expect(find.textContaining('Manual recovery'), findsWidgets);
    await _ensureEndKeyVisible(tester, const Key('move-dispatch-disabled'));
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('move-dispatch-disabled')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every offered delay passes the real planner delay rule',
      (tester) async {
    final api = MoveFake();
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    for (final choice in const [
      (300, '5 minutes'),
      (900, '15 minutes'),
      (1800, '30 minutes'),
    ]) {
      await _tapVisible(tester, const Key('move-delay'));
      await tester.tap(find.text(choice.$2).last);
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('move-empty-source-attestation'));
      await _tapVisible(tester, const Key('move-prepare'));
      expect(api.delay, choice.$1);
      final assessment = assessNetworkMove(
        now: DateTime.now().toUtc(),
        sourceCredentials: false,
        targetCredentials: false,
        distinctIdentities: false,
        discoveryComplete: false,
        sourceReads: const [],
        targetRead: null,
        targetIsSource: false,
        attestation: null,
        delaySeconds: api.delay!,
      );
      expect(assessment.blockers, isNot(contains('invalid_delay')));
      await _ensureVisible(tester, const Key('move-delay'));
    }
    expect(api.planCalls, 3);
  });

  testWidgets('ready review stops claiming readiness after expiry',
      (tester) async {
    final api = MoveFake()
      ..preparedPlan = _plan(
          decision: 'ready_for_lab_review',
          validUntil: DateTime.now().toUtc().add(const Duration(minutes: 1)));
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    expect(find.textContaining('Evidence ready for separate lab review'),
        findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
    expect(find.textContaining('review has expired'), findsOneWidget);
    expect(find.textContaining('Evidence ready for separate lab review'),
        findsNothing);
    await _ensureVisible(tester, const Key('move-dispatch-disabled'));
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('move-dispatch-disabled')))
            .onPressed,
        isNull);
  });
}
