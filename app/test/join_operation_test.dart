import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/join/join_assessment.dart';
import 'package:thread_network_tool/join/join_operation.dart';
import 'package:thread_network_tool/join/join_verification.dart';

void main() {
  final sent = DateTime.utc(2026, 10, 25, 12);
  const plan = JoinPlanSnapshot(
      sourceRouterId: 'router-A',
      sourceIdentity: null,
      targetRouterId: 'target-router',
      targetIdentity: 'target-id',
      model: 'Synthetic',
      firmware: '1',
      capability: DeviceCapability.supported,
      threadReadiness: ThreadReadiness.ready,
      sourceState: SourceState.vendorAttestedUncommissioned,
      emptySourceAttested: true,
      authorizedTargetCredentials: true,
      authorizedDeviceCommand: true);
  test('dispatch intent is one-use and uncertain result never retries', () {
    final planned = JoinOperation('random-op', JoinStage.planned);
    final confirmed = planned.reduce(JoinEvent.confirm, plan: plan);
    final sending = confirmed.reduce(JoinEvent.beginDispatch, at: sent);
    expect(sending.stage, JoinStage.dispatching);
    expect(sending.reduce(JoinEvent.beginDispatch, at: sent).stage,
        JoinStage.dispatching);
    final uncertain = sending.reduce(JoinEvent.dispatchUncertain);
    expect(uncertain.stage, JoinStage.needsAttention);
    expect(uncertain.reduce(JoinEvent.beginDispatch, at: sent).stage,
        JoinStage.needsAttention);
    expect(sending.reduce(JoinEvent.restoredAfterRestart).stage,
        JoinStage.needsAttention);
  });
  test('restart invalidates a confirmation that was never sent', () {
    final confirmed =
        JoinOperation('random-op', JoinStage.confirmed, confirmedPlan: plan);
    final restored = confirmed.reduce(JoinEvent.restoredAfterRestart);
    expect(restored.stage, JoinStage.planned);
    expect(restored.reduce(JoinEvent.beginDispatch, at: sent).stage,
        JoinStage.planned);
  });
  test('cancellation before send differs from stopping observation', () {
    final planned = JoinOperation('random-op', JoinStage.planned);
    expect(planned.reduce(JoinEvent.cancel).stage, JoinStage.cancelled);
    final observing = planned
        .reduce(JoinEvent.confirm, plan: plan)
        .reduce(JoinEvent.beginDispatch, at: sent)
        .reduce(JoinEvent.commandAccepted);
    expect(observing.reduce(JoinEvent.cancel).stage, JoinStage.observing);
    expect(observing.reduce(JoinEvent.stopObservation).stage,
        JoinStage.observationStopped);
  });
  test('pending verification preserves observation state', () {
    final observing =
        JoinOperation('random-op', JoinStage.observing, sentAt: sent);
    expect(observing.applyVerification(VerificationOutcome.pending).stage,
        JoinStage.observing);
  });
  test('persisted operation record contains no network or device values', () {
    final record = JoinOperation('random-op', JoinStage.dispatching,
            sentAt: sent, confirmedPlan: plan)
        .toRedactedJson();
    expect(record.keys,
        containsAll(['schema_version', 'operation_id', 'stage', 'sent_at']));
    expect(jsonEncode(record), isNot(contains('dataset')));
    expect(jsonEncode(record), isNot(contains('router')));
    expect(jsonEncode(record), isNot(contains('target-id')));
    expect(jsonEncode(record), isNot(contains('Synthetic')));
  });
}
