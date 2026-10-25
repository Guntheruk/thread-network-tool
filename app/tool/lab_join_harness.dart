import 'dart:async';
import 'dart:convert';
import 'package:thread_network_tool/join/join_assessment.dart';
import 'package:thread_network_tool/join/join_operation.dart';
import 'package:thread_network_tool/join/join_verification.dart';

/// Synthetic only. There is no network, vendor SDK, or SET implementation here.
enum SyntheticCommandOutcome { accepted, uncertain }

class SyntheticActuator {
  SyntheticActuator(this.outcome, {this.hold});
  final SyntheticCommandOutcome outcome;
  final Future<void>? hold;
  int calls = 0;

  Future<SyntheticCommandOutcome> send() async {
    calls++;
    if (hold != null) await hold;
    return outcome;
  }
}

class _Reservation {
  _Reservation(this.operation, this.sourceRouterId, this.targetRouterId,
      this.targetIdentity);
  JoinOperation operation;
  final String sourceRouterId;
  final String targetRouterId;
  final String targetIdentity;
}

class SyntheticLabHarness {
  SyntheticLabHarness(this.actuator);
  final SyntheticActuator actuator;
  final Map<String, _Reservation> _reservations = {};
  final Map<String, _Reservation> _sourceLeases = {};

  Future<JoinOperation> send(
      JoinOperation operation, JoinCandidate candidate, DateTime at) async {
    // Reserve synchronously before the first await. Even a caller retaining the
    // original immutable confirmed value cannot dispatch the same ID twice.
    final prior = _reservations[operation.operationId];
    if (prior != null) return prior.operation;
    final sourceLease = _sourceLeases[candidate.routerId];
    if (sourceLease != null) {
      // An uncertain or unfinished command must never be replayed under a
      // fresh operation ID. A completed earlier join can be followed only by
      // a separately reviewed move with post-dispatch source/target reads.
      final priorSentAt = sourceLease.operation.sentAt;
      final sourceRead = candidate.routerRead;
      if (sourceLease.operation.stage != JoinStage.complete ||
          priorSentAt == null ||
          candidate.sourceState != SourceState.verifiedExisting ||
          sourceRead == null ||
          !sourceRead.checkedAt.isAfter(priorSentAt) ||
          sourceRead.identity != sourceLease.targetIdentity ||
          !candidate.targetRead.checkedAt.isAfter(priorSentAt)) {
        return operation;
      }
    }
    if (assessJoin(candidate, at).decision != JoinDecision.readyForLabReview ||
        operation.stage != JoinStage.confirmed ||
        operation.confirmedPlan?.matches(candidate) != true ||
        operation.operationId.isEmpty) {
      return operation;
    }
    final next = operation.reduce(JoinEvent.beginDispatch, at: at);
    if (next.stage != JoinStage.dispatching) return next;
    final reservation = _Reservation(next, candidate.routerId,
        candidate.targetRead.routerId, candidate.targetIdentity);
    _reservations[operation.operationId] = reservation;
    _sourceLeases[candidate.routerId] = reservation;
    // A future hardware adapter must durably save this intent before dispatch.
    try {
      final outcome = await actuator.send();
      reservation.operation = next.reduce(
          outcome == SyntheticCommandOutcome.accepted
              ? JoinEvent.commandAccepted
              : JoinEvent.dispatchUncertain);
    } catch (_) {
      reservation.operation = next.reduce(JoinEvent.dispatchUncertain);
    }
    return reservation.operation;
  }

  /// Stop the authoritative observation, including callbacks already queued.
  /// This cannot undo a dispatched command or release an uncertain source.
  JoinOperation stopObservation(JoinOperation operation) {
    final reservation = _reservations[operation.operationId];
    if (reservation == null) {
      return operation.reduce(JoinEvent.stopObservation);
    }
    if (operation.sentAt == reservation.operation.sentAt) {
      reservation.operation =
          reservation.operation.reduce(JoinEvent.stopObservation);
    }
    return reservation.operation;
  }

  JoinOperation observe(
      JoinOperation operation, JoinVerification evidence, DateTime now) {
    final reservation = _reservations[operation.operationId];
    if (reservation == null) return operation;
    // Preserve a caller's reducer transition as well as the explicit harness
    // API. Later callbacks holding an older immutable value cannot revive it.
    if (operation.stage == JoinStage.observationStopped) {
      stopObservation(operation);
    }
    final current = reservation.operation;
    if (current.sentAt == null ||
        current.sentAt != evidence.sentAt ||
        reservation.sourceRouterId != evidence.routerId ||
        reservation.targetRouterId != evidence.targetRouterId ||
        reservation.targetIdentity != evidence.targetIdentity ||
        evidence.affectedAccessoryIds.isNotEmpty) {
      return current;
    }
    reservation.operation =
        current.applyVerification(verifyJoin(evidence, now));
    return reservation.operation;
  }
}

/// Demonstrates state transitions with synthetic evidence and no device access.
Future<void> main() async {
  final at = DateTime.utc(2026, 10, 25, 12);
  final readAt = at.subtract(const Duration(seconds: 10));
  final target = NetworkRead(
      routerId: 'synthetic-target-router',
      identity: 'synthetic-target',
      checkedAt: readAt,
      authenticated: true,
      activeRead: true,
      pending: PendingState.empty);
  final candidate = JoinCandidate(
      routerId: 'synthetic-source-router',
      targetIdentity: 'synthetic-target',
      model: 'Synthetic lab device',
      firmware: 'fixture-1',
      capability: DeviceCapability.supported,
      threadReadiness: ThreadReadiness.ready,
      authorizedTargetCredentials: true,
      authorizedDeviceCommand: true,
      sourceState: SourceState.vendorAttestedUncommissioned,
      emptySourceAttested: true,
      targetRead: target);
  final actuator = SyntheticActuator(SyntheticCommandOutcome.accepted);
  final harness = SyntheticLabHarness(actuator);
  var operation = JoinOperation('synthetic-operation', JoinStage.planned)
      .reduce(JoinEvent.confirm,
          plan: JoinPlanSnapshot.fromCandidate(candidate));
  operation = await harness.send(operation, candidate, at);
  final after = at.add(const Duration(seconds: 20));
  operation = harness.observe(
      operation,
      JoinVerification(
          routerId: 'synthetic-source-router',
          targetIdentity: 'synthetic-target',
          targetRouterId: 'synthetic-target-router',
          sentAt: at,
          routerRead: NetworkRead(
              routerId: 'synthetic-source-router',
              identity: 'synthetic-target',
              checkedAt: after,
              authenticated: true,
              activeRead: true,
              pending: PendingState.empty),
          targetRead: NetworkRead(
              routerId: 'synthetic-target-router',
              identity: 'synthetic-target',
              checkedAt: after,
              authenticated: true,
              activeRead: true,
              pending: PendingState.empty),
          accessories: AccessoryEvidence.noneAttested,
          observationComplete: true),
      after);
  // CLI demonstration output contains only the allowlisted operation record.
  // ignore: avoid_print
  print(jsonEncode(operation.toRedactedJson()));
}
