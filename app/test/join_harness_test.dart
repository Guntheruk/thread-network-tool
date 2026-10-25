import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/join/join_assessment.dart';
import 'package:thread_network_tool/join/join_operation.dart';
import 'package:thread_network_tool/join/join_verification.dart';
import '../tool/lab_join_harness.dart';

void main() {
  final at = DateTime.utc(2026, 10, 25, 12);
  JoinCandidate candidate({DateTime? readAt}) => JoinCandidate(
      routerId: 'synthetic-router',
      targetIdentity: 'target-id',
      model: 'Synthetic',
      firmware: '1',
      capability: DeviceCapability.supported,
      threadReadiness: ThreadReadiness.ready,
      authorizedTargetCredentials: true,
      authorizedDeviceCommand: true,
      sourceState: SourceState.vendorAttestedUncommissioned,
      emptySourceAttested: true,
      targetRead: NetworkRead(
          routerId: 'target-router',
          identity: 'target-id',
          checkedAt: readAt ?? at,
          authenticated: true,
          activeRead: true,
          pending: PendingState.empty));
  JoinOperation confirmed(JoinCandidate c, [String id = 'synthetic-op']) =>
      JoinOperation(id, JoinStage.planned)
          .reduce(JoinEvent.confirm, plan: JoinPlanSnapshot.fromCandidate(c));
  test('synthetic actuator is called once and duplicate send is inert',
      () async {
    final actuator = SyntheticActuator(SyntheticCommandOutcome.accepted);
    final harness = SyntheticLabHarness(actuator);
    final reviewed = candidate();
    final operation = confirmed(reviewed);
    final sent = await harness.send(operation, reviewed, at);
    expect(sent.stage, JoinStage.observing);
    final duplicate = await harness.send(sent, candidate(), at);
    expect(duplicate.stage, JoinStage.observing);
    expect(actuator.calls, 1);
  });
  test('concurrent reuse of original confirmed object dispatches once',
      () async {
    final gate = Completer<void>();
    final actuator =
        SyntheticActuator(SyntheticCommandOutcome.accepted, hold: gate.future);
    final harness = SyntheticLabHarness(actuator);
    final reviewed = candidate();
    final operation = confirmed(reviewed, 'same-operation');
    final first = harness.send(operation, reviewed, at);
    final second = harness.send(operation, reviewed, at);
    expect(actuator.calls, 1);
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(
        results.last.stage, anyOf(JoinStage.dispatching, JoinStage.observing));
    expect((await harness.send(operation, reviewed, at)).stage,
        JoinStage.observing);
    expect(actuator.calls, 1);
  });
  test('confirmation for one candidate cannot dispatch a substituted one',
      () async {
    final actuator = SyntheticActuator(SyntheticCommandOutcome.accepted);
    final harness = SyntheticLabHarness(actuator);
    final reviewed = candidate();
    final operation = JoinOperation('bound-op', JoinStage.planned).reduce(
        JoinEvent.confirm,
        plan: JoinPlanSnapshot.fromCandidate(reviewed));
    final substituted = candidate();
    final changed = JoinCandidate(
        routerId: 'other-router',
        targetIdentity: substituted.targetIdentity,
        model: substituted.model,
        firmware: substituted.firmware,
        capability: substituted.capability,
        threadReadiness: substituted.threadReadiness,
        authorizedTargetCredentials: substituted.authorizedTargetCredentials,
        authorizedDeviceCommand: substituted.authorizedDeviceCommand,
        sourceState: substituted.sourceState,
        emptySourceAttested: substituted.emptySourceAttested,
        targetRead: substituted.targetRead);
    expect((await harness.send(operation, changed, at)).stage,
        JoinStage.confirmed);
    expect(actuator.calls, 0);
    final changedFirmware = JoinCandidate(
        routerId: reviewed.routerId,
        targetIdentity: reviewed.targetIdentity,
        model: reviewed.model,
        firmware: 'unreviewed-firmware',
        capability: reviewed.capability,
        threadReadiness: reviewed.threadReadiness,
        authorizedTargetCredentials: reviewed.authorizedTargetCredentials,
        authorizedDeviceCommand: reviewed.authorizedDeviceCommand,
        sourceState: reviewed.sourceState,
        emptySourceAttested: reviewed.emptySourceAttested,
        targetRead: reviewed.targetRead);
    expect((await harness.send(operation, changedFirmware, at)).stage,
        JoinStage.confirmed);
    expect(actuator.calls, 0);
    expect((await harness.send(operation, reviewed, at)).stage,
        JoinStage.observing);
    expect(actuator.calls, 1);
  });
  test('stale evidence prevents even synthetic dispatch', () async {
    final actuator = SyntheticActuator(SyntheticCommandOutcome.accepted);
    final harness = SyntheticLabHarness(actuator);
    final stale = candidate(readAt: at.subtract(const Duration(minutes: 6)));
    final result = await harness.send(confirmed(stale), stale, at);
    expect(result.stage, JoinStage.confirmed);
    expect(actuator.calls, 0);
  });
  test('matching timestamp cannot substitute a different selected target',
      () async {
    final harness = SyntheticLabHarness(
        SyntheticActuator(SyntheticCommandOutcome.accepted));
    final reviewed = candidate();
    final sent = await harness.send(confirmed(reviewed), reviewed, at);
    final later = at.add(const Duration(seconds: 30));
    NetworkRead read(String id, String identity) => NetworkRead(
        routerId: id,
        identity: identity,
        checkedAt: later,
        authenticated: true,
        activeRead: true,
        pending: PendingState.empty);
    final substituted = harness.observe(
        sent,
        JoinVerification(
            routerId: 'synthetic-router',
            targetIdentity: 'different-target',
            targetRouterId: 'different-target-router',
            sentAt: at,
            routerRead: read('synthetic-router', 'different-target'),
            targetRead: read('different-target-router', 'different-target'),
            accessories: AccessoryEvidence.noneAttested,
            observationComplete: true),
        later);
    expect(substituted.stage, JoinStage.observing);
    final switchedRouter = harness.observe(
        sent,
        JoinVerification(
            routerId: 'synthetic-router',
            targetIdentity: 'target-id',
            targetRouterId: 'another-target-router',
            sentAt: at,
            routerRead: read('synthetic-router', 'target-id'),
            targetRead: read('another-target-router', 'target-id'),
            accessories: AccessoryEvidence.noneAttested,
            observationComplete: true),
        later);
    expect(switchedRouter.stage, JoinStage.observing);
  });
  test('ambiguous synthetic result enters attention without replay', () async {
    final actuator = SyntheticActuator(SyntheticCommandOutcome.uncertain);
    final harness = SyntheticLabHarness(actuator);
    final reviewed = candidate();
    final result = await harness.send(confirmed(reviewed), reviewed, at);
    expect(result.stage, JoinStage.needsAttention);
    await harness.send(result, candidate(), at);
    expect(actuator.calls, 1);
  });
  test('an interim observation can later complete', () async {
    final reviewed = candidate();
    final harness = SyntheticLabHarness(
        SyntheticActuator(SyntheticCommandOutcome.accepted));
    final sent = await harness.send(confirmed(reviewed), reviewed, at);
    final later = at.add(const Duration(seconds: 30));
    NetworkRead read(String id) => NetworkRead(
        routerId: id,
        identity: 'target-id',
        checkedAt: later,
        authenticated: true,
        activeRead: true,
        pending: PendingState.empty);
    JoinVerification evidence(bool done) => JoinVerification(
        routerId: 'synthetic-router',
        targetIdentity: 'target-id',
        targetRouterId: 'target-router',
        sentAt: at,
        routerRead: read('synthetic-router'),
        targetRead: read('target-router'),
        accessories: AccessoryEvidence.noneAttested,
        observationComplete: done);
    expect(harness.observe(sent, evidence(false), later).stage,
        JoinStage.observing);
    expect(
        harness.observe(sent, evidence(true), later).stage, JoinStage.complete);
  });
}
