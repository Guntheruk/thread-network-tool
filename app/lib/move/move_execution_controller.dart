import 'move_execution.dart';
import 'move_journal.dart';

typedef MovePreflightCall = Future<MovePreflight> Function(MoveExecutionPlan);
typedef MoveWorkerCall = Future<MoveWorkerResult> Function(MoveExecutionPlan);
typedef MoveObserveCall = Future<MoveObservation> Function(MoveRecord);

/// One native-only authoritative controller. The UI supplies a reviewed ID to
/// its session, which resolves the immutable plan; it does not construct plans.
class MoveExecutionController {
  MoveExecutionController({
    required this.journal,
    required this.preflight,
    required this.worker,
    required this.observe,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final MoveJournal journal;
  final MovePreflightCall preflight;
  final MoveWorkerCall worker;
  final MoveObserveCall observe;
  final DateTime Function() now;
  final Map<String, Future<MoveRecord>> _starts = {};
  bool _busy = false;
  Future<void>? _initialization;
  final Set<String> _knownOperations = {};
  final Map<String, Future<MoveRecord?>> _recoveries = {};

  // A controller must invalidate continuity inherited from a previous owner
  // before exposing or observing it. Share the in-flight initialization so
  // concurrent entry points cannot race recovery against their own reads.
  Future<void> _initialize() {
    final existing = _initialization;
    if (existing != null) return existing;
    late final Future<void> attempt;
    attempt = _recover().then<void>((_) {}).catchError((
      Object error,
      StackTrace stack,
    ) {
      if (identical(_initialization, attempt)) _initialization = null;
      Error.throwWithStackTrace(error, stack);
    });
    return _initialization = attempt;
  }

  /// Duplicate calls receive the same future. This reservation precedes any
  /// await; the durable global journal also fences other app processes.
  Future<MoveRecord> confirmAndStart(MoveExecutionPlan plan) {
    final existing = _starts[plan.operationId];
    if (existing != null) return existing;
    if (_busy) {
      return Future.error(const MoveExecutionFailure('operation_busy'));
    }
    _busy = true;
    final result = _start(plan).whenComplete(() {
      _busy = false;
      _starts.remove(plan.operationId);
    });
    _starts[plan.operationId] = result;
    return result;
  }

  Future<MoveRecord> _start(MoveExecutionPlan plan) async {
    await _initialize();
    if (plan.profileId != isolatedMoveProfile) {
      throw const MoveExecutionFailure('unsupported_profile');
    }
    if (!now().isBefore(plan.expiresAt)) {
      throw const MoveExecutionFailure('review_expired');
    }
    final current = await this.current();
    if (current != null && current.operationId == plan.operationId) {
      return current;
    }
    if (current != null && !current.terminal) {
      throw const MoveExecutionFailure('unresolved_operation');
    }
    final MovePreflight check;
    try {
      check = await preflight(plan);
    } catch (_) {
      throw const MoveExecutionFailure('preflight_failed');
    }
    final at = now().toUtc();
    if (!at.isBefore(plan.expiresAt) ||
        check.checkedAt.isAfter(at) ||
        at.difference(check.checkedAt) > const Duration(seconds: 30)) {
      throw const MoveExecutionFailure('review_expired');
    }
    if (!check.profileVerified ||
        !check.runtimeVerified ||
        !check.workerHasIndependentDeadline) {
      throw const MoveExecutionFailure('execution_unavailable');
    }
    if (check.blockers.isNotEmpty ||
        check.bindingCommitment != plan.bindingCommitment) {
      throw const MoveExecutionFailure('review_invalidated');
    }
    var record = MoveRecord(
      operationId: plan.operationId,
      revision: 1,
      profileId: plan.profileId,
      stage: MoveStage.dispatchFenced,
      disposition: MoveDisposition.unknown,
      sourceCommitment: plan.sourceCommitment,
      targetCommitment: plan.targetCommitment,
      targetRouterBinding: plan.targetRouterBinding,
      routerBindings: plan.routerBindings.toList()..sort(),
      fencedAt: at,
      observeUntil: at.add(
        Duration(seconds: plan.delaySeconds + plan.observationSeconds),
      ),
      observationSeconds: plan.observationSeconds,
      reason: 'none',
    );
    // A failed/uncertain journal acknowledgement never permits worker launch.
    record = await journal.begin(record);
    _knownOperations.add(record.operationId);
    MoveDisposition disposition;
    var reason = 'worker_uncertain';
    try {
      final result = await worker(plan);
      disposition =
          result.operationId == plan.operationId &&
              result.disposition != MoveDisposition.unknown
          ? result.disposition
          : MoveDisposition.uncertain;
      reason = switch (disposition) {
        MoveDisposition.accepted => 'worker_accepted',
        MoveDisposition.rejected => 'worker_rejected',
        MoveDisposition.provenNotSent => 'worker_not_sent',
        _ => 'worker_uncertain',
      };
    } catch (_) {
      disposition = MoveDisposition.uncertain;
      reason = 'worker_failure';
    }
    final stage = switch (disposition) {
      MoveDisposition.accepted => MoveStage.observing,
      MoveDisposition.provenNotSent => MoveStage.provenNotSent,
      _ => MoveStage.needsAttention,
    };
    final next = record.next(stage, reason, nextDisposition: disposition);
    try {
      return await journal.update(next, record.revision);
    } catch (_) {
      // The durable fence remains authoritative. A different observer may have
      // advanced it, or its persistence may be uncertain: never send again.
      throw const MoveExecutionFailure('journal_after_dispatch_uncertain');
    }
  }

  Future<MoveRecord?> current() async {
    await _initialize();
    final record = await journal.read();
    if (record == null || _knownOperations.contains(record.operationId)) {
      return record;
    }
    // Initialization may have happened before another process began this
    // operation. Adopt each unfamiliar operation with the same recovery rule.
    await _recoveries.putIfAbsent(record.operationId, () {
      late final Future<MoveRecord?> attempt;
      attempt = _recover(record).catchError((Object error, StackTrace stack) {
        if (identical(_recoveries[record.operationId], attempt)) {
          _recoveries.remove(record.operationId);
        }
        Error.throwWithStackTrace(error, stack);
      });
      return attempt;
    });
    return current();
  }

  /// Restores display/recovery state only. No plan or dispatch capability is
  /// reconstructed from disk, and this path cannot call the worker.
  Future<MoveRecord?> restore() async {
    if (_initialization == null) {
      await _initialize();
      return current();
    }
    await _initialize();
    return _recover();
  }

  Future<MoveRecord?> _recover([MoveRecord? inherited]) async {
    final record = inherited ?? await journal.read();
    if (record == null ||
        record.terminal ||
        record.stage == MoveStage.observationStopped) {
      if (record != null) _knownOperations.add(record.operationId);
      return record;
    }
    final recovered = await journal.update(
      record.next(
        MoveStage.needsAttention,
        'restart_requires_reads',
        nextDisposition: record.disposition == MoveDisposition.unknown
            ? MoveDisposition.uncertain
            : null,
        resetStability: true,
      ),
      record.revision,
    );
    _knownOperations.add(record.operationId);
    return recovered;
  }

  Future<MoveRecord> stopObservation(String operationId) async {
    final record = await _record(operationId);
    if (record.terminal || record.stage == MoveStage.observationStopped) {
      return record;
    }
    return journal.update(
      record.next(
        MoveStage.observationStopped,
        'observation_stopped',
        resetStability: true,
        nextDisposition: record.disposition == MoveDisposition.unknown
            ? MoveDisposition.uncertain
            : null,
      ),
      record.revision,
    );
  }

  /// Explicit read-only recovery can resume an observation the person stopped.
  /// A stale in-flight observation cannot revive it because all updates use CAS.
  Future<MoveRecord> checkOutcome(
    String operationId, {
    bool resume = false,
  }) async {
    var record = await _record(operationId);
    if (record.terminal ||
        (record.stage == MoveStage.observationStopped && !resume)) {
      return record;
    }
    if (record.stage == MoveStage.dispatchFenced) {
      record = await journal.update(
        record.next(
          MoveStage.needsAttention,
          'restart_requires_reads',
          nextDisposition: MoveDisposition.uncertain,
        ),
        record.revision,
      );
    }
    final MoveObservation evidence;
    try {
      evidence = await observe(record);
    } catch (_) {
      final current = await _record(operationId);
      if (current.revision != record.revision) return current;
      return journal.update(
        record.next(
          MoveStage.needsAttention,
          'verification_failed',
          resetStability: true,
        ),
        record.revision,
      );
    }
    // Check the authoritative revision after await: stop/another process wins.
    final current = await _record(operationId);
    if (current.revision != record.revision) return current;
    final at = now().toUtc();
    if (evidence.operationId != operationId ||
        !evidence.recoveryBindingVerified) {
      return journal.update(
        record.next(
          MoveStage.needsAttention,
          'recovery_binding_mismatch',
          resetStability: true,
        ),
        record.revision,
      );
    }
    bool valid(MoveRouterObservation value, String expectedCommitment) =>
        value.authenticated &&
        value.pendingEmpty &&
        value.connectivityVerified &&
        value.datasetCommitment == expectedCommitment &&
        value.checkedAt.isAfter(record.fencedAt) &&
        (record.stableLast == null ||
            value.checkedAt.isAfter(record.stableLast!)) &&
        !value.checkedAt.isAfter(at) &&
        at.difference(value.checkedAt) <= const Duration(seconds: 30);
    final bindings = evidence.sources.map((e) => e.binding).toList()..sort();
    // A definite native rejection can be reconciled as unchanged. An uncertain
    // send can never use this route: a delayed accepted update may look unchanged.
    final rejected = record.disposition == MoveDisposition.rejected;
    final matching =
        bindings.join(',') == record.routerBindings.join(',') &&
        evidence.sources.every(
          (e) => valid(
            e,
            rejected ? record.sourceCommitment : record.targetCommitment,
          ),
        ) &&
        evidence.target.binding == record.targetRouterBinding &&
        valid(evidence.target, record.targetCommitment);
    final samples = [evidence.target, ...evidence.sources];
    final sampleAt = samples
        .map((e) => e.checkedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final continuous =
        record.stableLast != null &&
        !record.stableLast!.isAfter(at) &&
        at.difference(record.stableLast!) <= const Duration(seconds: 30);
    final since = matching
        ? (continuous ? record.stableSince : sampleAt)
        : null;
    final complete =
        matching &&
        evidence.workerTerminated &&
        !at.isBefore(record.observeUntil) &&
        !sampleAt.isBefore(record.observeUntil) &&
        since != null &&
        sampleAt.difference(since) >=
            Duration(seconds: record.observationSeconds);
    final waiting = matching || at.isBefore(record.observeUntil);
    return journal.update(
      record.next(
        complete
            ? rejected
                  ? MoveStage.verifiedUnchanged
                  : MoveStage.verifiedComplete
            : waiting
            ? MoveStage.observing
            : MoveStage.needsAttention,
        complete
            ? rejected
                  ? 'verification_unchanged'
                  : 'verification_complete'
            : waiting
            ? 'verification_pending'
            : 'verification_failed',
        nextStableSince: since,
        nextStableLast: matching ? sampleAt : null,
        resetStability: !matching,
      ),
      record.revision,
    );
  }

  Future<MoveRecord> _record(String operationId) async {
    final record = await current();
    if (record == null || record.operationId != operationId) {
      throw const MoveExecutionFailure('unknown_operation');
    }
    return record;
  }
}
