/// The first execution profile is an isolated OpenThread lab route. This name
/// does not establish support for eero, HomePod, Nest, or other vendor devices.
const isolatedMoveProfile = 'openthread-posix-lab-v1';

enum MoveStage {
  dispatchFenced('dispatch_fenced'),
  observing('observing'),
  needsAttention('needs_attention'),
  observationStopped('observation_stopped'),
  verifiedComplete('verified_complete'),
  verifiedUnchanged('verified_unchanged'),
  provenNotSent('proven_not_sent');

  const MoveStage(this.wire);
  final String wire;
}

enum MoveDisposition {
  unknown('unknown'),
  accepted('accepted'),
  rejected('rejected'),
  uncertain('uncertain'),
  provenNotSent('proven_not_sent');

  const MoveDisposition(this.wire);
  final String wire;
}

const moveReasons = {
  'none',
  'worker_accepted',
  'worker_rejected',
  'worker_not_sent',
  'worker_uncertain',
  'worker_failure',
  'journal_failure',
  'restart_requires_reads',
  'credentials_required',
  'recovery_binding_mismatch',
  'verification_pending',
  'verification_failed',
  'verification_complete',
  'verification_unchanged',
  'observation_stopped',
};

bool moveCommitmentValid(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

class MoveExecutionFailure implements Exception {
  const MoveExecutionFailure(this.code);
  final String code;
  @override
  String toString() => 'MoveExecutionFailure($code)';
}

/// Trusted session-owned plan, not an input DTO accepted from a UI/HTTP client.
/// Commitments come from canonical, complete native snapshots. Secrets and
/// endpoints stay in the adapter's private request, outside this model.
class MoveExecutionPlan {
  MoveExecutionPlan({
    required this.reviewId,
    required this.operationId,
    required this.profileId,
    required this.bindingCommitment,
    required this.sourceCommitment,
    required this.targetCommitment,
    required this.targetRouterBinding,
    required List<String> routerBindings,
    required this.expiresAt,
    required this.delaySeconds,
    required this.observationSeconds,
  }) : routerBindings = List.unmodifiable(routerBindings) {
    if (![
          reviewId,
          operationId,
          bindingCommitment,
          sourceCommitment,
          targetCommitment,
          targetRouterBinding,
          ...routerBindings,
        ].every(moveCommitmentValid) ||
        sourceCommitment == targetCommitment ||
        routerBindings.contains(targetRouterBinding) ||
        routerBindings.isEmpty ||
        routerBindings.length > 32 ||
        routerBindings.toSet().length != routerBindings.length ||
        delaySeconds < 300 ||
        delaySeconds > 86400 ||
        observationSeconds < 1 ||
        observationSeconds > 3600) {
      throw const MoveExecutionFailure('invalid_plan');
    }
  }
  final String reviewId;
  final String operationId;
  final String profileId;
  final String bindingCommitment;
  final String sourceCommitment;
  final String targetCommitment;
  final String targetRouterBinding;
  final List<String> routerBindings;
  final DateTime expiresAt;
  final int delaySeconds;
  final int observationSeconds;
}

/// This evidence is produced by the trusted native/session adapter immediately
/// before dispatch. It is never populated from client-asserted readiness flags.
class MovePreflight {
  const MovePreflight({
    required this.bindingCommitment,
    required this.checkedAt,
    required this.profileVerified,
    required this.runtimeVerified,
    required this.workerHasIndependentDeadline,
    this.blockers = const [],
  });
  final String bindingCommitment;
  final DateTime checkedAt;
  final bool profileVerified;
  final bool runtimeVerified;
  final bool workerHasIndependentDeadline;
  final List<String> blockers;
}

class MoveWorkerResult {
  const MoveWorkerResult(this.operationId, this.disposition);
  final String operationId;
  final MoveDisposition disposition;
}

/// Private local recovery metadata. This is not the report/export schema.
class MoveRecord {
  MoveRecord({
    required this.operationId,
    required this.revision,
    required this.profileId,
    required this.stage,
    required this.disposition,
    required this.sourceCommitment,
    required this.targetCommitment,
    required this.targetRouterBinding,
    required List<String> routerBindings,
    required this.fencedAt,
    required this.observeUntil,
    required this.observationSeconds,
    this.stableSince,
    this.stableLast,
    required this.reason,
  }) : routerBindings = List.unmodifiable(routerBindings) {
    if (![
          operationId,
          sourceCommitment,
          targetCommitment,
          targetRouterBinding,
          ...routerBindings,
        ].every(moveCommitmentValid) ||
        revision < 1 ||
        revision > 9007199254740991 ||
        profileId != isolatedMoveProfile ||
        sourceCommitment == targetCommitment ||
        routerBindings.contains(targetRouterBinding) ||
        routerBindings.isEmpty ||
        routerBindings.length > 32 ||
        routerBindings.toSet().length != routerBindings.length ||
        routerBindings.join(',') !=
            (routerBindings.toList()..sort()).join(',') ||
        fencedAt.millisecondsSinceEpoch <= 0 ||
        !observeUntil.isAfter(fencedAt) ||
        observationSeconds < 1 ||
        observationSeconds > 3600 ||
        ((stableSince == null) != (stableLast == null)) ||
        (stableSince != null &&
            (!stableSince!.isAfter(fencedAt) ||
                stableLast!.isBefore(stableSince!))) ||
        !moveReasons.contains(reason) ||
        (stage == MoveStage.dispatchFenced &&
            (disposition != MoveDisposition.unknown ||
                reason != 'none' ||
                stableSince != null)) ||
        (stage == MoveStage.provenNotSent &&
            disposition != MoveDisposition.provenNotSent) ||
        (stage == MoveStage.verifiedComplete &&
            !{
              MoveDisposition.accepted,
              MoveDisposition.uncertain,
            }.contains(disposition)) ||
        (stage == MoveStage.verifiedUnchanged &&
            disposition != MoveDisposition.rejected) ||
        ({
              MoveStage.verifiedComplete,
              MoveStage.verifiedUnchanged,
            }.contains(stage) &&
            (stableSince == null ||
                stableLast!.isBefore(observeUntil) ||
                stableLast!.difference(stableSince!) <
                    Duration(seconds: observationSeconds)))) {
      throw const MoveExecutionFailure('invalid_record');
    }
  }

  final String operationId;
  final int revision;
  final String profileId;
  final MoveStage stage;
  final MoveDisposition disposition;
  final String sourceCommitment;
  final String targetCommitment;
  final String targetRouterBinding;
  final List<String> routerBindings;
  final DateTime fencedAt;
  final DateTime observeUntil;
  final int observationSeconds;
  final DateTime? stableSince;
  final DateTime? stableLast;
  final String reason;
  bool get terminal =>
      stage == MoveStage.verifiedComplete ||
      stage == MoveStage.verifiedUnchanged ||
      stage == MoveStage.provenNotSent;

  MoveRecord next(
    MoveStage nextStage,
    String nextReason, {
    MoveDisposition? nextDisposition,
    DateTime? nextStableSince,
    DateTime? nextStableLast,
    bool resetStability = false,
  }) => MoveRecord(
    operationId: operationId,
    revision: revision + 1,
    profileId: profileId,
    stage: nextStage,
    disposition: nextDisposition ?? disposition,
    sourceCommitment: sourceCommitment,
    targetCommitment: targetCommitment,
    targetRouterBinding: targetRouterBinding,
    routerBindings: routerBindings,
    fencedAt: fencedAt,
    observeUntil: observeUntil,
    observationSeconds: observationSeconds,
    stableSince: resetStability ? null : nextStableSince ?? stableSince,
    stableLast: resetStability ? null : nextStableLast ?? stableLast,
    reason: nextReason,
  );

  String encode() =>
      'schema=1\noperation=$operationId\nrevision=$revision\n'
      'profile=$profileId\nstage=${stage.wire}\ndisposition=${disposition.wire}\n'
      'source=$sourceCommitment\ntarget=$targetCommitment\n'
      'target_router=$targetRouterBinding\nrouters=${routerBindings.join(',')}\n'
      'fenced_at_ms=${fencedAt.millisecondsSinceEpoch}\n'
      'observe_until_ms=${observeUntil.millisecondsSinceEpoch}\n'
      'observation_seconds=$observationSeconds\n'
      'stable_since_ms=${stableSince?.millisecondsSinceEpoch ?? 0}\n'
      'stable_last_ms=${stableLast?.millisecondsSinceEpoch ?? 0}\nreason=$reason\n';

  static MoveRecord decode(String text) {
    try {
      if (text.length > 8192 || !text.endsWith('\n')) {
        throw const FormatException();
      }
      final fields = <String, String>{};
      for (final line in text.substring(0, text.length - 1).split('\n')) {
        final at = line.indexOf('=');
        if (at < 1 || fields.containsKey(line.substring(0, at))) {
          throw const FormatException();
        }
        fields[line.substring(0, at)] = line.substring(at + 1);
      }
      if (fields.length != 16 || fields['schema'] != '1') {
        throw const FormatException();
      }
      DateTime? stableTime(String field) => fields[field] == '0'
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              int.parse(fields[field]!),
              isUtc: true,
            );
      final record = MoveRecord(
        operationId: fields['operation']!,
        revision: int.parse(fields['revision']!),
        profileId: fields['profile']!,
        stage: MoveStage.values.singleWhere((v) => v.wire == fields['stage']),
        disposition: MoveDisposition.values.singleWhere(
          (v) => v.wire == fields['disposition'],
        ),
        sourceCommitment: fields['source']!,
        targetCommitment: fields['target']!,
        targetRouterBinding: fields['target_router']!,
        routerBindings: fields['routers']!.split(','),
        fencedAt: DateTime.fromMillisecondsSinceEpoch(
          int.parse(fields['fenced_at_ms']!),
          isUtc: true,
        ),
        observeUntil: DateTime.fromMillisecondsSinceEpoch(
          int.parse(fields['observe_until_ms']!),
          isUtc: true,
        ),
        reason: fields['reason']!,
        observationSeconds: int.parse(fields['observation_seconds']!),
        stableSince: stableTime('stable_since_ms'),
        stableLast: stableTime('stable_last_ms'),
      );
      if (record.encode() != text) throw const FormatException();
      return record;
    } catch (_) {
      throw const MoveExecutionFailure('journal_unavailable');
    }
  }
}

class MoveRouterObservation {
  const MoveRouterObservation({
    required this.binding,
    required this.datasetCommitment,
    required this.checkedAt,
    required this.authenticated,
    required this.pendingEmpty,
    required this.connectivityVerified,
  });
  final String binding;
  final String datasetCommitment;
  final DateTime checkedAt;
  final bool authenticated;
  final bool pendingEmpty;
  final bool connectivityVerified;
}

class MoveObservation {
  const MoveObservation({
    required this.operationId,
    required this.recoveryBindingVerified,
    required this.workerTerminated,
    required this.sources,
    required this.target,
  });
  final String operationId;
  final bool recoveryBindingVerified;
  final bool workerTerminated;
  final List<MoveRouterObservation> sources;
  final MoveRouterObservation target;
}
