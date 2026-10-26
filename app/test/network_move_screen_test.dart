import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/live_api.dart';
import 'package:thread_network_tool/move/network_move_plan.dart';
import 'package:thread_network_tool/network_move_screen.dart';
import 'support/isolated_action.dart';

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
  String reviewId = 'review-id',
  DateTime? validUntil,
}) =>
    NetworkMovePlan.fromJson({
      'schema_version': 1,
      'mode': 'network_move_review',
      'decision': decision,
      'blockers': decision == 'needs_evidence'
          ? ['source_read_missing_or_stale']
          : <String>[],
      'review_id': reviewId,
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
  NetworkMovePlan? activePlan;
  Future<NetworkMovePlan?> Function()? onCurrentPlan;

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
    current = LiveState.fromJson(
      _stateJson(
        source: role == 'source' || current.sourceCredentialAvailable,
        target: role == 'target' || current.targetCredentialAvailable,
      ),
    );
    return current;
  }

  @override
  Future<LiveState> probeForRole(String role, String routerId) async {
    probeRoles.add(role);
    probeRouters.add(routerId);
    return current;
  }

  @override
  Future<NetworkMovePlan> networkMovePlan({
    required String targetRouterId,
    required EmptySourceAttestationInput attestation,
    required int delaySeconds,
  }) async {
    planCalls++;
    plannedTarget = targetRouterId;
    this.attestation = attestation;
    delay = delaySeconds;
    activePlan = preparedPlan ?? _plan();
    return activePlan!;
  }

  @override
  Future<NetworkMovePlan?> currentNetworkMovePlan() async =>
      onCurrentPlan == null ? activePlan : await onCurrentPlan!();
}

class ExecutionMoveFake extends MoveFake implements NetworkMoveExecutionApi {
  @override
  bool get executionAvailable => true;
  @override
  bool get executionRecoveryAvailable => true;
  NetworkMoveExecutionStatus? status;
  final actions = <String>[];
  bool failConfirm = false;
  bool failCurrent = false;

  @override
  Future<NetworkMoveExecutionReview> prepareExecution(String reviewId) async {
    actions.add('prepare:$reviewId');
    return NetworkMoveExecutionReview.fromJson({
      'schema_version': 1,
      'mode': 'network_move_execution_review',
      'review_id': reviewId,
      'operation_id': 'operation-1',
      'profile_id': 'openthread-posix-lab-v1',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 2))
          .toIso8601String(),
      'source_router_ids': ['source-a', 'source-b'],
      'target_router_id': 'target-id',
      'delay_seconds': 300,
      'observation_seconds': 30,
    });
  }

  @override
  Future<NetworkMoveExecutionStatus> confirmExecution(String reviewId) async {
    actions.add('confirm:$reviewId');
    if (failConfirm) throw const LiveApiException();
    return status = _status('observing');
  }

  @override
  Future<NetworkMoveExecutionStatus?> currentExecution() async {
    actions.add('current');
    if (failCurrent) throw const LiveApiException();
    return status;
  }

  @override
  Future<NetworkMoveExecutionStatus> checkExecution(
    String operationId, {
    bool resume = false,
  }) async {
    actions.add('check:$operationId:$resume');
    return status = _status('needs_attention');
  }

  @override
  Future<NetworkMoveExecutionStatus> stopExecution(String operationId) async {
    actions.add('stop:$operationId');
    return status = _status('observation_stopped');
  }

  NetworkMoveExecutionStatus _status(String stage) =>
      NetworkMoveExecutionStatus.fromJson({
        'schema_version': 1,
        'mode': 'network_move_execution_status',
        'operation_id': 'operation-1',
        'profile_id': 'openthread-posix-lab-v1',
        'stage': stage,
        'disposition': 'uncertain',
        'reason': stage == 'observation_stopped'
            ? 'observation_stopped'
            : 'worker_uncertain',
      });
}

class MacExecutionMoveFake extends ExecutionMoveFake
    implements ExecutionProfileInfo {
  @override
  String get executionProfileId => 'eero-source-network-alpha-v1';
}

Future<void> _pump(
  WidgetTester tester,
  MoveFake api, {
  Size size = const Size(900, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: NetworkMoveScreen(api: api, initialState: api.current),
      ),
    ),
  );
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
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    final position = scrollable.position;
    if (position.pixels <= position.minScrollExtent) break;
    final step = position.viewportDimension / 2;
    position.jumpTo(
      (position.pixels - step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in [
    (
      'verified_unchanged',
      'rejected',
      'verification_unchanged',
      'Network settings unchanged'
    ),
    (
      'proven_not_sent',
      'proven_not_sent',
      'worker_not_sent',
      'Join was not sent'
    ),
  ]) {
    testWidgets(
        'Mac terminal ${entry.$1} shows a final result and permits a fresh review',
        (tester) async {
      final api = MacExecutionMoveFake()
        ..status = NetworkMoveExecutionStatus.fromJson({
          'schema_version': 1,
          'mode': 'network_move_execution_status',
          'operation_id': 'operation-1',
          'profile_id': 'eero-source-network-alpha-v1',
          'stage': entry.$1,
          'disposition': entry.$2,
          'reason': entry.$3,
        });
      await _pump(tester, api);
      expect(find.text(entry.$4), findsOneWidget);
      expect(find.text('Checking network settings'), findsNothing);
      expect(
          find.text(
              'Do not start another join while this outcome is unresolved.'),
          findsNothing);
      await _tapVisible(tester, const Key('move-new-review'));
      expect(api.actions.where((a) => a.startsWith('confirm:')), isEmpty);
      expect(find.text(entry.$4), findsNothing);
    });
  }
  testWidgets(
      'runtime helper refuses a current-status-blocked execution action',
      (tester) async {
    final api = ExecutionMoveFake()..failCurrent = true;
    await _pump(tester, api, size: const Size(1200, 2000));
    var blocked = 0;
    await expectLater(
      ensureIsolatedAction(tester, 'move-execution-prepare',
          onBlocked: () => blocked++),
      throwsStateError,
    );
    expect(blocked, 1);
    expect(
        api.actions.where((action) => action.startsWith('prepare:')), isEmpty);
    expect(
        find.textContaining('Execution status is unavailable'), findsOneWidget);
  });
  for (final height in [900.0, 2000.0]) {
    testWidgets(
      'runtime helper reaches execution preparation after lazy review at $height',
      (tester) async {
        final api = ExecutionMoveFake()
          ..preparedPlan = _plan(
            decision: 'ready_for_lab_review',
            validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
          );
        // Three routers at both the actual runtime viewport and a smaller
        // viewport; inserting the review leaves execution controls unbuilt.
        await _pump(tester, api, size: Size(1200, height));
        await _tapVisible(tester, const Key('move-target-target-id'));
        await _tapVisible(tester, const Key('move-empty-source-attestation'));
        await _tapVisible(tester, const Key('move-prepare'));
        expect(find.byKey(const Key('move-review')), findsOneWidget);
        expect(find.byKey(const Key('move-execution-prepare')), findsNothing);
        expect(api.actions.where((action) => action.startsWith('prepare:')),
            isEmpty);
        await ensureIsolatedAction(tester, 'move-execution-prepare');
        await tester.tap(find.byKey(const Key('move-execution-prepare')));
        await tester.pumpAndSettle();
        expect(
            api.actions.where((action) => action == 'prepare:review-id').length,
            1);
        expect(find.byKey(const Key('move-execution-confirm')), findsOneWidget);
      },
    );
  }
  testWidgets(
    'isolated execution requires separate preparation and confirmation',
    (tester) async {
      final api = ExecutionMoveFake()
        ..preparedPlan = _plan(
          decision: 'ready_for_lab_review',
          validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
        );
      await _pump(tester, api);
      expect(api.actions, ['current']);
      await _ensureVisible(tester, const Key('move-execution-prepare'));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('move-execution-prepare')),
            )
            .onPressed,
        isNull,
      );
      await _tapVisible(tester, const Key('move-target-target-id'));
      await _tapVisible(tester, const Key('move-empty-source-attestation'));
      await _tapVisible(tester, const Key('move-prepare'));
      await _tapVisible(tester, const Key('move-execution-prepare'));
      expect(api.actions, ['current', 'prepare:review-id']);
      expect(
        find.textContaining('Network to move must have no attached devices'),
        findsOneWidget,
      );
      await _tapVisible(tester, const Key('move-execution-confirm'));
      expect(api.actions, [
        'current',
        'prepare:review-id',
        'confirm:review-id',
      ]);
      await _tapVisible(tester, const Key('move-execution-check'));
      expect(api.actions.last, 'check:operation-1:false');
    },
  );

  testWidgets('uncertain confirmation never offers a resend', (tester) async {
    final api = ExecutionMoveFake()
      ..failConfirm = true
      ..preparedPlan = _plan(
        decision: 'ready_for_lab_review',
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      );
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    await _tapVisible(tester, const Key('move-execution-prepare'));
    await _tapVisible(tester, const Key('move-execution-confirm'));
    await _ensureVisible(tester, const Key('move-execution-confirm'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-execution-confirm')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Do not submit again'), findsOneWidget);
    await _tapVisible(tester, const Key('move-execution-current'));
    expect(
      api.actions.where((action) => action.startsWith('confirm:')).length,
      1,
    );
  });

  testWidgets(
    'opening restores a fenced operation without preparing a review',
    (tester) async {
      final api = ExecutionMoveFake()
        ..status = NetworkMoveExecutionStatus.fromJson({
          'schema_version': 1,
          'mode': 'network_move_execution_status',
          'operation_id': 'operation-1',
          'profile_id': 'openthread-posix-lab-v1',
          'stage': 'needs_attention',
          'disposition': 'uncertain',
          'reason': 'restart_requires_reads',
        });
      await _pump(tester, api);
      await _ensureVisible(tester, const Key('move-execution-stage'));
      expect(find.textContaining('needs attention'), findsOneWidget);
      expect(find.byKey(const Key('move-execution-confirm')), findsNothing);
      expect(api.actions, ['current']);
    },
  );
  testWidgets('failed current-status lookup blocks execution preparation', (
    tester,
  ) async {
    final api = ExecutionMoveFake()
      ..failCurrent = true
      ..preparedPlan = _plan(
        decision: 'ready_for_lab_review',
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      );
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    await _ensureVisible(tester, const Key('move-execution-prepare'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-execution-prepare')))
          .onPressed,
      isNull,
    );
    expect(
        api.actions.where((action) => action.startsWith('prepare:')), isEmpty);
  });

  testWidgets('attestation is off and plan never runs from selection alone', (
    tester,
  ) async {
    final api = MoveFake();
    await _pump(tester, api);
    await _ensureVisible(tester, const Key('move-empty-source-attestation'));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('move-empty-source-attestation')),
          )
          .value,
      false,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-prepare')))
          .onPressed,
      isNull,
    );
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _ensureVisible(tester, const Key('move-prepare'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-prepare')))
          .onPressed,
      isNull,
    );
    expect(api.planCalls, 0);
    await _ensureEndKeyVisible(tester, const Key('move-dispatch-disabled'));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('move-dispatch-disabled')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('access dialog cancel does not import either role', (
    tester,
  ) async {
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

  testWidgets(
      'Mac move review requires separate eero and whole-group attestations',
      (tester) async {
    final api = MacExecutionMoveFake()
      ..preparedPlan = _plan(
        decision: 'ready_for_execution_review',
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      );
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _ensureVisible(tester, const Key('move-prepare'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-prepare')))
          .onPressed,
      isNull,
    );
    await _tapVisible(tester, const Key('move-eero-source-attestation'));
    await _tapVisible(tester, const Key('move-whole-eero-group-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    expect(api.planCalls, 1);
    expect(api.attestation!.operatorEeroSource, isTrue);
    expect(api.attestation!.allSourceEerosRepresented, isTrue);
    expect(find.textContaining('Settings checked. Review the join'),
        findsOneWidget);
  });

  testWidgets('target and source setup and checks keep explicit roles', (
    tester,
  ) async {
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

  testWidgets(
    'explicit attestation prepares a read-only whole-network review',
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
      expect(find.textContaining('accessories are not moved'), findsOneWidget);
      expect(
        find.textContaining('Offline or unobserved devices'),
        findsWidgets,
      );
      expect(find.textContaining('Manual recovery'), findsWidgets);
      await _ensureEndKeyVisible(tester, const Key('move-dispatch-disabled'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('move-dispatch-disabled')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every offered delay passes the real planner delay rule', (
    tester,
  ) async {
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

  testWidgets('ready review stops claiming readiness after expiry', (
    tester,
  ) async {
    final api = MoveFake()
      ..preparedPlan = _plan(
        decision: 'ready_for_lab_review',
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    expect(
      find.textContaining('Evidence ready for separate lab review'),
      findsOneWidget,
    );
    await tester.pump(const Duration(minutes: 2));
    expect(find.textContaining('review has expired'), findsOneWidget);
    expect(
      find.textContaining('Evidence ready for separate lab review'),
      findsNothing,
    );
    await _ensureVisible(tester, const Key('move-dispatch-disabled'));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('move-dispatch-disabled')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'resume hides readiness until the authoritative review is checked',
    (tester) async {
      final pending = Completer<NetworkMovePlan?>();
      final api = MoveFake()
        ..preparedPlan = _plan(
          decision: 'ready_for_lab_review',
          validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
        )
        ..onCurrentPlan = () => pending.future;
      await _pump(tester, api);
      await _tapVisible(tester, const Key('move-target-target-id'));
      await _tapVisible(tester, const Key('move-empty-source-attestation'));
      await _tapVisible(tester, const Key('move-prepare'));
      expect(
        find.textContaining('Evidence ready for separate lab review'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        find.textContaining('Evidence ready for separate lab review'),
        findsNothing,
      );
      expect(
        find.textContaining('Checking whether this review is still current'),
        findsOneWidget,
      );
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('review is no longer current'),
        findsOneWidget,
      );
    },
  );

  testWidgets('changed review ID and lookup error both remove a ready claim', (
    tester,
  ) async {
    final api = MoveFake()
      ..preparedPlan = _plan(
        decision: 'ready_for_lab_review',
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      );
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    api.activePlan = _plan(
      reviewId: 'other-review',
      decision: 'ready_for_lab_review',
      validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Evidence ready for separate lab review'),
      findsNothing,
    );
    expect(find.textContaining('review is no longer current'), findsOneWidget);

    await _tapVisible(tester, const Key('move-prepare'));
    api.onCurrentPlan = () async => throw StateError('lookup failed');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Evidence ready for separate lab review'),
      findsNothing,
    );
    expect(find.textContaining('review could not be verified'), findsOneWidget);
  });

  testWidgets('late old lookup cannot erase a newer prepared review', (
    tester,
  ) async {
    final pending = Completer<NetworkMovePlan?>();
    var lookups = 0;
    final api = MoveFake()
      ..preparedPlan = _plan(
        decision: 'ready_for_lab_review',
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      );
    api.onCurrentPlan = () {
      lookups++;
      return lookups == 1 ? pending.future : Future.value(api.activePlan);
    };
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    await tester.pump(const Duration(seconds: 5));
    api.preparedPlan = _plan(
      reviewId: 'new-review',
      decision: 'ready_for_lab_review',
      validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
    );
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(api.activePlan!.reviewId, 'new-review');
    expect(
      find.textContaining('Evidence ready for separate lab review'),
      findsOneWidget,
    );
    expect(find.textContaining('review is no longer current'), findsNothing);
  });

  testWidgets('resume ignores a lookup started before the app was hidden', (
    tester,
  ) async {
    final pending = Completer<NetworkMovePlan?>();
    var lookups = 0;
    final api = MoveFake()
      ..preparedPlan = _plan(
        decision: 'ready_for_lab_review',
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      );
    api.onCurrentPlan = () {
      lookups++;
      return lookups == 1 ? pending.future : Future.value(null);
    };
    await _pump(tester, api);
    await _tapVisible(tester, const Key('move-target-target-id'));
    await _tapVisible(tester, const Key('move-empty-source-attestation'));
    await _tapVisible(tester, const Key('move-prepare'));
    await tester.pump(const Duration(seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      find.textContaining('Evidence ready for separate lab review'),
      findsNothing,
    );
    pending.complete(api.activePlan);
    await tester.pumpAndSettle();
    expect(lookups, 2);
    expect(
      find.textContaining('Evidence ready for separate lab review'),
      findsNothing,
    );
    expect(find.textContaining('review is no longer current'), findsOneWidget);
  });
}
