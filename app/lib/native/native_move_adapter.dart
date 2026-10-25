import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../move/move_execution.dart';
import '../move/move_execution_controller.dart';
import '../move/native_move_journal.dart';
import 'native_move_diagnostic.dart';

/// Private IPC to the isolated simulator supervisor. This is never a household
/// discovery/provider fallback and never uses a TCP listener.
class IsolatedFixtureClient {
  const IsolatedFixtureClient(this.socketPath);
  final String socketPath;

  Future<Map<String, dynamic>> call(String action) async {
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 5),
    );
    try {
      socket.write('${jsonEncode({'action': action})}\n');
      await socket.flush();
      var bytes = 0;
      final line = await socket
          .transform<List<int>>(StreamTransformer.fromHandlers(
            handleData: (data, sink) {
              bytes += data.length;
              if (bytes > 65536) {
                sink.addError(const FormatException('fixture_output'));
              } else {
                sink.add(data);
              }
            },
          ))
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 25));
      final value = jsonDecode(line);
      if (value is! Map<String, dynamic> || value['error'] != null) {
        throw const MoveExecutionFailure('fixture_unavailable');
      }
      return value;
    } finally {
      socket.destroy();
    }
  }
}

/// Secret-bearing immutable request; never a public API DTO or journal record.
class NativeMoveRequest {
  const NativeMoveRequest({
    required this.operationId,
    required this.reviewId,
    required this.sourceDataset,
    required this.targetDataset,
    required this.sourceGeneration,
    required this.targetGeneration,
    required this.sessionId,
    required this.discoveryRevision,
    required this.connectivityRevision,
    required this.sourceNodes,
    required this.targetNode,
    required this.inventoryAttestation,
  });
  final String operationId, reviewId, sourceDataset, targetDataset;
  final int sourceGeneration, targetGeneration;
  final String sessionId, discoveryRevision, connectivityRevision;
  final List<String> sourceNodes;
  final String targetNode, inventoryAttestation;

  String encode(String mode, NativeMoveAdapter adapter,
          {String expectedBinding = '-', int fencedAtMs = 0}) =>
      'TNT-APP-MOVE/1\nmode $mode\noperation_id $operationId\n'
      'review_revision $reviewId\nsource_generation $sourceGeneration\n'
      'target_generation $targetGeneration\nsession_id $sessionId\n'
      'discovery_revision $discoveryRevision\n'
      'connectivity_revision $connectivityRevision\n'
      'source_dataset $sourceDataset\ntarget_dataset $targetDataset\n'
      'fixture_manifest ${adapter.manifestPath}\nsource_count ${sourceNodes.length}\n'
      '${sourceNodes.map((id) => 'source_node $id\n').join()}'
      'target_node $targetNode\ndelay_ms 300000\n'
      'inventory_attestation $inventoryAttestation\n'
      'lifecycle_directory ${adapter.lifecycleDirectory}\n'
      'fenced_at_ms $fencedAtMs\nexpected_binding $expectedBinding\nEND\n';
}

class _PreparedMove {
  const _PreparedMove(this.request, this.plan);
  final NativeMoveRequest request;
  final MoveExecutionPlan plan;
}

/// Only constructed by an explicit isolated test/development entry point.
/// Production platform routing does not instantiate this adapter.
class NativeMoveAdapter {
  NativeMoveAdapter({
    required this.workerExecutable,
    required this.manifestPath,
    required this.lifecycleDirectory,
    required this.fixture,
    required this.journal,
  }) {
    controller = MoveExecutionController(
      journal: journal,
      preflight: _preflight,
      worker: _dispatch,
      observe: _observe,
    );
  }
  final String workerExecutable, manifestPath, lifecycleDirectory;
  final IsolatedFixtureClient fixture;
  final NativeMoveJournal journal;
  late final MoveExecutionController controller;
  final Map<String, _PreparedMove> _prepared = {};
  String? _recoverySource, _recoveryTarget;
  int _sourceGeneration = 0, _targetGeneration = 0;
  String? _sessionId, _discoveryRevision;
  Future<void>? _initializing;
  int dispatchLaunches = 0;
  int? lastDispatchPetitions;
  int? lastDispatchSetInvocations;

  /// Explicit isolated test hook; ordinary app construction emits no markers.
  void Function(NativePreparationDiagnostic)? onPreparationFailure;

  bool get available =>
      Platform.isLinux &&
      File(workerExecutable).isAbsolute &&
      File(workerExecutable).existsSync() &&
      File(manifestPath).isAbsolute &&
      File(manifestPath).existsSync();

  Future<void> initialize() => _initializing ??= journal.initialize();

  void credentialsChanged(
      {required String? source,
      required String? target,
      required int sourceGeneration,
      required int targetGeneration,
      required String sessionId,
      required String discoveryRevision}) {
    _prepared.clear();
    _recoverySource = source;
    _recoveryTarget = target;
    _sourceGeneration = sourceGeneration;
    _targetGeneration = targetGeneration;
    _sessionId = sessionId;
    _discoveryRevision = discoveryRevision;
  }

  void invalidateReviews() => _prepared.clear();

  Future<MoveExecutionPlan> prepare(NativeMoveRequest request) async {
    var stage = NativePreparationStage.journal;
    Map<String, dynamic>? nativeResult;
    try {
      await initialize();
      stage = NativePreparationStage.recovery;
      final existing = await controller.current();
      if (existing != null && !existing.terminal) {
        throw const MoveExecutionFailure('unresolved_operation');
      }
      stage = NativePreparationStage.fixtureRefresh;
      await fixture.call('refresh');
      stage = NativePreparationStage.nativeProcess;
      final result = await _run(request.encode('inspect', this));
      nativeResult = result;
      stage = result['ready'] == true
          ? NativePreparationStage.evidence : NativePreparationStage.nativeResult;
      _requireEvidence(result, request.operationId);
      if (result['ready'] != true) {
        throw const MoveExecutionFailure('preflight_failed');
      }
      stage = NativePreparationStage.plan;
      final checked = _time(result['checked_at_ms']);
      final plan = MoveExecutionPlan(
        reviewId: request.reviewId,
        operationId: request.operationId,
        profileId: isolatedMoveProfile,
        bindingCommitment: _commitment(result['binding_commitment']),
        sourceCommitment: _commitment(result['source_commitment']),
        targetCommitment: _commitment(result['target_commitment']),
        targetRouterBinding: _commitment(result['target_binding']),
        routerBindings: _commitments(result['source_bindings']),
        expiresAt: checked.add(const Duration(seconds: 30)),
        delaySeconds: 300,
        observationSeconds: 30,
      );
      _prepared[request.operationId] = _PreparedMove(request, plan);
      return plan;
    } catch (failure) {
      final NativePreparationDiagnostic diagnostic;
      if (stage == NativePreparationStage.nativeResult &&
          nativeResult != null) {
        diagnostic = NativePreparationDiagnostic.nativeRefusal(
            nativeResult, request.operationId);
      } else {
        final code = switch (stage) {
          NativePreparationStage.journal => 'journal_failure',
          NativePreparationStage.recovery =>
            failure is MoveExecutionFailure && failure.code == 'unresolved_operation'
                ? 'unresolved_operation' : 'journal_failure',
          NativePreparationStage.fixtureRefresh => 'fixture_unavailable',
          NativePreparationStage.nativeProcess => 'worker_failure',
          NativePreparationStage.evidence =>
            failure is MoveExecutionFailure && failure.code == 'review_expired'
                ? 'review_expired'
                : 'invalid_native_evidence',
          NativePreparationStage.plan => 'invalid_plan',
          _ => 'worker_failure',
        };
        diagnostic = NativePreparationDiagnostic.fixed(stage, code);
      }
      try {
        onPreparationFailure?.call(diagnostic);
      } catch (_) {
        // Diagnostics cannot change the failure or grant dispatch authority.
      }
      rethrow;
    }
  }

  MoveExecutionPlan resolveReview(String reviewId) => _prepared.values
      .singleWhere((value) => value.plan.reviewId == reviewId,
          orElse: () => throw const MoveExecutionFailure('review_invalidated'))
      .plan;

  Future<MovePreflight> _preflight(MoveExecutionPlan plan) async {
    final prepared = _prepared[plan.operationId];
    if (prepared == null || prepared.plan != plan) {
      throw const MoveExecutionFailure('review_invalidated');
    }
    await fixture.call('refresh');
    final result = await _run(prepared.request.encode('inspect', this));
    _requireEvidence(result, plan.operationId);
    if (result['ready'] != true) {
      throw const MoveExecutionFailure('preflight_failed');
    }
    return MovePreflight(
      bindingCommitment: _commitment(result['binding_commitment']),
      checkedAt: _time(result['checked_at_ms']),
      profileVerified: result['profile_verified'] == true,
      runtimeVerified: result['runtime_verified'] == true,
      workerHasIndependentDeadline: result['independent_deadline'] == true,
    );
  }

  Future<MoveWorkerResult> _dispatch(MoveExecutionPlan plan) async {
    final prepared = _prepared.remove(plan.operationId);
    if (prepared == null) {
      throw const MoveExecutionFailure('review_invalidated');
    }
    // The controller invokes this only after its native durable journal.begin.
    // Re-read that exact fence here; no dispatch process can start on a failed ack.
    final record = await journal.read();
    if (record == null ||
        record.operationId != plan.operationId ||
        record.stage != MoveStage.dispatchFenced ||
        record.sourceCommitment != plan.sourceCommitment ||
        record.targetCommitment != plan.targetCommitment) {
      throw const MoveExecutionFailure('unresolved_operation');
    }
    dispatchLaunches++;
    final result = await _run(
        prepared.request.encode('dispatch', this,
            expectedBinding: plan.bindingCommitment,
            fencedAtMs: record.fencedAt.millisecondsSinceEpoch),
        dispatch: true);
    var disposition = MoveDisposition.values.firstWhere(
      (value) => value.wire == result['disposition'],
      orElse: () => MoveDisposition.uncertain,
    );
    final petitions = result['petitions'];
    final sets = result['pending_set_invocations'];
    if (petitions is int && (petitions == 0 || petitions == 1)) {
      lastDispatchPetitions = petitions;
    }
    if (sets is int && (sets == 0 || sets == 1)) {
      lastDispatchSetInvocations = sets;
    }
    if (result['operation_id'] != plan.operationId ||
        (disposition == MoveDisposition.provenNotSent && sets != 0) ||
        ((disposition == MoveDisposition.accepted ||
                disposition == MoveDisposition.rejected) &&
            (sets != 1 || petitions != 1))) {
      disposition = MoveDisposition.uncertain;
    }
    return MoveWorkerResult(
        result['operation_id'] is String
            ? result['operation_id'] as String
            : '',
        disposition);
  }

  Future<MoveObservation> _observe(MoveRecord record) async {
    if (_recoverySource == null ||
        _recoveryTarget == null ||
        _sessionId == null ||
        _discoveryRevision == null) {
      throw const MoveExecutionFailure('credentials_required');
    }
    final bootstrap = await fixture.call('bootstrap');
    await fixture.call('refresh');
    final request = NativeMoveRequest(
      operationId: record.operationId,
      reviewId: record.operationId,
      sourceDataset: _recoverySource!,
      targetDataset: _recoveryTarget!,
      sourceGeneration: _sourceGeneration,
      targetGeneration: _targetGeneration,
      sessionId: _sessionId!,
      discoveryRevision: _discoveryRevision!,
      connectivityRevision: _commitment(bootstrap['fixture_id']),
      sourceNodes: _commitments(bootstrap['source_node_ids']),
      targetNode: _commitment(bootstrap['target_node_id']),
      inventoryAttestation: record.operationId,
    );
    final result = await _run(request.encode('observe', this,
        fencedAtMs: record.fencedAt.millisecondsSinceEpoch));
    _requireEvidence(result, record.operationId);
    MoveRouterObservation router(Object? value) {
      if (value is! Map<String, dynamic>) throw const FormatException();
      return MoveRouterObservation(
        binding: _commitment(value['binding']),
        datasetCommitment: _commitment(value['dataset_commitment']),
        checkedAt: _time(value['checked_at_ms']),
        authenticated: value['authenticated'] == true,
        pendingEmpty: value['pending_empty'] == true,
        connectivityVerified: value['connectivity_verified'] == true,
      );
    }

    final rows = result['sources'];
    if (rows is! List || rows.isEmpty || rows.length > 8) {
      throw const FormatException();
    }
    return MoveObservation(
      operationId: record.operationId,
      recoveryBindingVerified: result['recovery_binding_verified'] == true &&
          result['source_commitment'] == record.sourceCommitment &&
          result['target_commitment'] == record.targetCommitment,
      workerTerminated: result['worker_terminated'] == true,
      sources: rows.map(router).toList(growable: false),
      target: router(result['target']),
    );
  }

  Future<Map<String, dynamic>> _run(String input,
      {bool dispatch = false}) async {
    if (!available) throw const MoveExecutionFailure('execution_unavailable');
    Process? child;
    Timer? timer;
    var invalid = false;
    try {
      child =
          await Process.start(workerExecutable, const [], runInShell: false);
      final process = child;
      final bytes = <int>[];
      var errors = 0;
      final outDone = process.stdout.listen((chunk) {
        if (bytes.length + chunk.length > 16384) {
          invalid = true;
          process.kill(ProcessSignal.sigkill);
        } else {
          bytes.addAll(chunk);
        }
      }).asFuture<void>();
      final errDone = process.stderr.listen((chunk) {
        errors += chunk.length;
        if (errors > 16384) {
          invalid = true;
          process.kill(ProcessSignal.sigkill);
        }
      }).asFuture<void>();
      timer = Timer(Duration(seconds: dispatch ? 1010 : 120), () {
        invalid = true;
        process.kill(ProcessSignal.sigkill);
      });
      process.stdin.write(input);
      await process.stdin.close();
      await process
          .exitCode; // OS exit, never a parent wait-timeout death claim.
      await Future.wait([outDone, errDone]);
      if (invalid) throw const FormatException();
      final result = jsonDecode(utf8.decode(bytes));
      if (result is! Map<String, dynamic> || result['schema_version'] != 1) {
        throw const FormatException();
      }
      return result;
    } catch (_) {
      if (child != null) {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
      }
      throw const MoveExecutionFailure('worker_failure');
    } finally {
      timer?.cancel();
    }
  }

  void _requireEvidence(Map<String, dynamic> result, String operationId) {
    if (result['operation_id'] != operationId ||
        result['profile_id'] != isolatedMoveProfile ||
        result['profile_verified'] != true ||
        result['runtime_verified'] != true ||
        result['independent_deadline'] != true) {
      throw const MoveExecutionFailure('execution_unavailable');
    }
    final at = _time(result['checked_at_ms']);
    final now = DateTime.now().toUtc();
    if (at.isAfter(now) || now.difference(at) > const Duration(seconds: 30)) {
      throw const MoveExecutionFailure('review_expired');
    }
  }

  static DateTime _time(Object? value) {
    if (value is! int || value <= 0) throw const FormatException();
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static String _commitment(Object? value) {
    if (value is! String || !moveCommitmentValid(value)) {
      throw const FormatException();
    }
    return value;
  }

  static List<String> _commitments(Object? value) {
    if (value is! List || value.isEmpty || value.length > 8) {
      throw const FormatException();
    }
    final result = value.map(_commitment).toList(growable: false);
    if (result.toSet().length != result.length) throw const FormatException();
    return result;
  }
}
