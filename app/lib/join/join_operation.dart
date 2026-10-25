import 'join_assessment.dart';
import 'join_verification.dart';

enum JoinStage {
  planned,
  confirmed,
  dispatching,
  observing,
  complete,
  needsAttention,
  cancelled,
  observationStopped,
}

enum JoinEvent {
  confirm,
  beginDispatch,
  commandAccepted,
  dispatchUncertain,
  cancel,
  stopObservation,
  restoredAfterRestart,
}

/// In-memory copy of the reviewed operation. It is never serialized.
class JoinPlanSnapshot {
  const JoinPlanSnapshot({
    required this.sourceRouterId,
    required this.sourceIdentity,
    required this.targetRouterId,
    required this.targetIdentity,
    required this.model,
    required this.firmware,
    required this.capability,
    required this.threadReadiness,
    required this.sourceState,
    required this.emptySourceAttested,
    required this.authorizedTargetCredentials,
    required this.authorizedDeviceCommand,
  });

  factory JoinPlanSnapshot.fromCandidate(JoinCandidate c) => JoinPlanSnapshot(
        sourceRouterId: c.routerId,
        sourceIdentity: c.routerRead?.identity,
        targetRouterId: c.targetRead.routerId,
        targetIdentity: c.targetIdentity,
        model: c.model,
        firmware: c.firmware,
        capability: c.capability,
        threadReadiness: c.threadReadiness,
        sourceState: c.sourceState,
        emptySourceAttested: c.emptySourceAttested,
        authorizedTargetCredentials: c.authorizedTargetCredentials,
        authorizedDeviceCommand: c.authorizedDeviceCommand,
      );

  final String sourceRouterId;
  final String? sourceIdentity;
  final String targetRouterId;
  final String targetIdentity;
  final String model;
  final String firmware;
  final DeviceCapability capability;
  final ThreadReadiness threadReadiness;
  final SourceState sourceState;
  final bool emptySourceAttested;
  final bool authorizedTargetCredentials;
  final bool authorizedDeviceCommand;

  bool matches(JoinCandidate c) =>
      sourceRouterId == c.routerId &&
      sourceIdentity == c.routerRead?.identity &&
      targetRouterId == c.targetRead.routerId &&
      targetIdentity == c.targetIdentity &&
      model == c.model &&
      firmware == c.firmware &&
      capability == c.capability &&
      threadReadiness == c.threadReadiness &&
      sourceState == c.sourceState &&
      emptySourceAttested == c.emptySourceAttested &&
      authorizedTargetCredentials == c.authorizedTargetCredentials &&
      authorizedDeviceCommand == c.authorizedDeviceCommand;
}

/// A redacted record. It intentionally has no router, network or credential IDs.
class JoinOperation {
  const JoinOperation(this.operationId, this.stage,
      {this.sentAt, this.confirmedPlan});
  final String operationId;
  final JoinStage stage;
  final DateTime? sentAt;
  final JoinPlanSnapshot? confirmedPlan;

  JoinOperation reduce(JoinEvent event,
      {DateTime? at, JoinPlanSnapshot? plan}) {
    if (event == JoinEvent.restoredAfterRestart) {
      if (stage == JoinStage.confirmed) {
        return JoinOperation(operationId, JoinStage.planned);
      }
      if (stage == JoinStage.dispatching || stage == JoinStage.observing) {
        return JoinOperation(operationId, JoinStage.needsAttention,
            sentAt: sentAt);
      }
      return this;
    }
    if (event == JoinEvent.cancel &&
        (stage == JoinStage.planned || stage == JoinStage.confirmed)) {
      return JoinOperation(operationId, JoinStage.cancelled);
    }
    if (event == JoinEvent.stopObservation && stage == JoinStage.observing) {
      return JoinOperation(operationId, JoinStage.observationStopped,
          sentAt: sentAt);
    }
    if (stage == JoinStage.planned &&
        event == JoinEvent.confirm &&
        plan != null) {
      return JoinOperation(operationId, JoinStage.confirmed,
          confirmedPlan: plan);
    }
    if (stage == JoinStage.confirmed &&
        event == JoinEvent.beginDispatch &&
        at != null &&
        confirmedPlan != null) {
      // Persist this intent *before* calling the injected actuator.
      return JoinOperation(operationId, JoinStage.dispatching,
          sentAt: at, confirmedPlan: confirmedPlan);
    }
    if (stage == JoinStage.dispatching && event == JoinEvent.commandAccepted) {
      return JoinOperation(operationId, JoinStage.observing,
          sentAt: sentAt, confirmedPlan: confirmedPlan);
    }
    if (stage == JoinStage.dispatching &&
        event == JoinEvent.dispatchUncertain) {
      return JoinOperation(operationId, JoinStage.needsAttention,
          sentAt: sentAt);
    }
    return this;
  }

  JoinOperation applyVerification(VerificationOutcome result) {
    if (stage != JoinStage.observing) return this;
    if (result == VerificationOutcome.pending) return this;
    return JoinOperation(
        operationId,
        result == VerificationOutcome.complete
            ? JoinStage.complete
            : JoinStage.needsAttention,
        sentAt: sentAt);
  }

  Map<String, Object?> toRedactedJson() => {
        'schema_version': 1,
        'operation_id': operationId,
        'stage': stage.name,
        'sent_at': sentAt?.toUtc().toIso8601String(),
      };
}
