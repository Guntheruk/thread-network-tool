import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../move/move_execution.dart';
import '../move/move_execution_controller.dart';
import '../move/native_move_journal.dart';
import 'move_adapter.dart';

const macMoveProfile = 'eero-source-network-alpha-v1';

/// A private correlation handle for one discovered numeric endpoint. It is not
/// proof of router manufacture or physical identity. A changed endpoint cannot
/// be rebound to an unresolved operation by an advertisement or network name.
class MacMoveRouter {
  MacMoveRouter(String address, this.port)
      : address = _numeric(address),
        identity = _identity(_numeric(address), port) {
    if (port < 1 || port > 65535) throw const FormatException();
  }

  final String address;
  final int port;
  final String identity;

  static String _numeric(String value) {
    final parsed = InternetAddress.tryParse(value);
    if (parsed == null || parsed.isLoopback || parsed.isMulticast) {
      throw const FormatException();
    }
    return parsed.address;
  }

  static String _identity(String address, int port) => sha256
      .convert(utf8.encode('TNT-MAC-ENDPOINT/1\n$address\n$port\n'))
      .toString();

  String get binding => sha256
      .convert(utf8.encode('TNT-MAC-ROUTER/1\n$identity\n$address\n$port\n'))
      .toString();

  String get wire => '$identity $address $port';
}

/// Secret-bearing request stays in memory and crosses to the worker only on
/// stdin. The native worker independently authenticates full Active/Pending
/// datasets and checks the original endpoint group again before the one SET.
class MacMoveRequest {
  const MacMoveRequest({
    required this.operationId,
    required this.reviewId,
    required this.sourceDataset,
    required this.targetDataset,
    required this.sourceGeneration,
    required this.targetGeneration,
    required this.sessionId,
    required this.discoveryRevision,
    required this.connectivityRevision,
    required this.sources,
    required this.target,
    required this.inventoryAttestation,
  });

  final String operationId, reviewId, sourceDataset, targetDataset;
  final int sourceGeneration, targetGeneration;
  final String sessionId, discoveryRevision, connectivityRevision;
  final List<MacMoveRouter> sources;
  final MacMoveRouter target;
  final String inventoryAttestation;

  List<MacMoveRouter> get orderedSources => List<MacMoveRouter>.of(sources)
    ..sort((a, b) => a.binding.compareTo(b.binding));

  String encode(String mode, String lifecycleDirectory,
          {String expectedBinding = '-', int fencedAtMs = 0}) =>
      'TNT-MAC-MOVE/1\nmode $mode\noperation_id $operationId\n'
      'review_revision $reviewId\nsource_generation $sourceGeneration\n'
      'target_generation $targetGeneration\nsession_id $sessionId\n'
      'discovery_revision $discoveryRevision\n'
      'connectivity_revision $connectivityRevision\n'
      'source_dataset $sourceDataset\ntarget_dataset $targetDataset\n'
      'source_count ${sources.length}\n'
      '${orderedSources.map((router) => 'source_router ${router.wire}\n').join()}'
      'target_router ${target.wire}\ndelay_ms 300000\n'
      'inventory_attestation $inventoryAttestation\n'
      'controlled_empty yes\nmanual_recovery yes\n'
      'lifecycle_directory $lifecycleDirectory\n'
      'fenced_at_ms $fencedAtMs\nexpected_binding $expectedBinding\nEND\n';
}

class _PreparedMacMove {
  const _PreparedMacMove(this.request, this.plan);
  final MacMoveRequest request;
  final MoveExecutionPlan plan;
}

/// Explicit Mac execution capability; never constructed on web/mobile or from
/// the isolated fixture entry point. All successful claims are configuration
/// verification only. This adapter does not retry, reset, or roll back.
class MacMoveAdapter implements MoveAdapter {
  MacMoveAdapter({
    required this.workerExecutable,
    required this.lifecycleDirectory,
    required this.journal,
  }) {
    controller = MoveExecutionController(
      journal: journal,
      preflight: _preflight,
      worker: _dispatch,
      observe: _observe,
    );
  }

  final String workerExecutable, lifecycleDirectory;
  final NativeMoveJournal journal;
  @override
  late final MoveExecutionController controller;
  final Map<String, _PreparedMacMove> _prepared = {};
  final Map<String, MacMoveRouter> _endpoints = {};
  String? _recoverySource, _recoveryTarget;
  int _sourceGeneration = 0, _targetGeneration = 0;
  String? _sessionId, _discoveryRevision;
  Future<void>? _initializing;
  int dispatchLaunches = 0;

  @override
  bool get available =>
      Platform.isMacOS &&
      File(workerExecutable).isAbsolute &&
      File(workerExecutable).existsSync() &&
      Directory(lifecycleDirectory).isAbsolute;

  @override
  Future<void> initialize() {
    final existing = _initializing;
    if (existing != null) return existing;
    late final Future<void> attempt;
    attempt = journal.initialize().catchError((Object error, StackTrace stack) {
      if (identical(_initializing, attempt)) _initializing = null;
      Error.throwWithStackTrace(error, stack);
    });
    return _initializing = attempt;
  }

  @override
  void credentialsChanged({
    required String? source,
    required String? target,
    required int sourceGeneration,
    required int targetGeneration,
    required String sessionId,
    required String discoveryRevision,
  }) {
    _prepared.clear();
    _recoverySource = source;
    _recoveryTarget = target;
    _sourceGeneration = sourceGeneration;
    _targetGeneration = targetGeneration;
    _sessionId = sessionId;
    _discoveryRevision = discoveryRevision;
  }

  /// Called after fresh discovery. Endpoints are candidates only; observation
  /// matches their exact native binding against the durable record.
  void endpointsChanged(Iterable<MacMoveRouter> routers) {
    _prepared.clear();
    _endpoints
      ..clear()
      ..addEntries(routers.map((router) => MapEntry(router.binding, router)));
  }

  @override
  void invalidateReviews() => _prepared.clear();

  Future<MoveExecutionPlan> prepare(MacMoveRequest request) async {
    await initialize();
    final existing = await controller.current();
    if (existing != null && !existing.terminal) {
      throw const MoveExecutionFailure('unresolved_operation');
    }
    if (request.sources.isEmpty ||
        request.sources.length > 8 ||
        request.sources.map((e) => e.identity).toSet().length !=
            request.sources.length ||
        request.sources.any((e) => e.identity == request.target.identity) ||
        !moveCommitmentValid(request.inventoryAttestation)) {
      throw const MoveExecutionFailure('invalid_plan');
    }
    final result = await _run(request.encode('inspect', lifecycleDirectory));
    _requireEvidence(result, request.operationId);
    if (result['ready'] != true) {
      throw const MoveExecutionFailure('preflight_failed');
    }
    final plan = MoveExecutionPlan(
      reviewId: request.reviewId,
      operationId: request.operationId,
      profileId: macMoveProfile,
      bindingCommitment: _commitment(result['binding_commitment']),
      sourceCommitment: _commitment(result['source_commitment']),
      targetCommitment: _commitment(result['target_commitment']),
      targetRouterBinding: _commitment(result['target_binding']),
      routerBindings: _commitments(result['source_bindings']),
      expiresAt:
          _time(result['checked_at_ms']).add(const Duration(seconds: 30)),
      delaySeconds: 300,
      observationSeconds: 30,
    );
    if (plan.routerBindings.length != request.sources.length ||
        plan.routerBindings
            .toSet()
            .difference(
              request.sources.map((e) => e.binding).toSet(),
            )
            .isNotEmpty ||
        plan.targetRouterBinding != request.target.binding) {
      throw const MoveExecutionFailure('invalid_native_evidence');
    }
    _prepared[plan.operationId] = _PreparedMacMove(request, plan);
    return plan;
  }

  @override
  MoveExecutionPlan resolveReview(String reviewId) => _prepared.values
      .singleWhere((value) => value.plan.reviewId == reviewId,
          orElse: () => throw const MoveExecutionFailure('review_invalidated'))
      .plan;

  Future<MovePreflight> _preflight(MoveExecutionPlan plan) async {
    final prepared = _prepared[plan.operationId];
    if (prepared == null || !identical(prepared.plan, plan)) {
      throw const MoveExecutionFailure('review_invalidated');
    }
    final result =
        await _run(prepared.request.encode('inspect', lifecycleDirectory));
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
    final record = await journal.read();
    if (record == null ||
        record.operationId != plan.operationId ||
        record.stage != MoveStage.dispatchFenced ||
        record.profileId != macMoveProfile ||
        record.sourceCommitment != plan.sourceCommitment ||
        record.targetCommitment != plan.targetCommitment) {
      throw const MoveExecutionFailure('unresolved_operation');
    }
    dispatchLaunches++;
    final result = await _run(
      prepared.request.encode('dispatch', lifecycleDirectory,
          expectedBinding: plan.bindingCommitment,
          fencedAtMs: record.fencedAt.millisecondsSinceEpoch),
      dispatch: true,
    );
    var disposition = MoveDisposition.values.firstWhere(
      (value) => value.wire == result['disposition'],
      orElse: () => MoveDisposition.uncertain,
    );
    final petitions = result['petitions'];
    final sets = result['pending_set_invocations'];
    if (result['operation_id'] != plan.operationId ||
        result['profile_id'] != macMoveProfile ||
        (disposition == MoveDisposition.provenNotSent &&
            (sets != 0 || petitions != 0)) ||
        ((disposition == MoveDisposition.accepted ||
                disposition == MoveDisposition.rejected) &&
            (sets != 1 || petitions != 1))) {
      disposition = MoveDisposition.uncertain;
    }
    return MoveWorkerResult(plan.operationId, disposition);
  }

  Future<MoveObservation> _observe(MoveRecord record) async {
    if (_recoverySource == null ||
        _recoveryTarget == null ||
        _sessionId == null ||
        _discoveryRevision == null) {
      throw const MoveExecutionFailure('credentials_required');
    }
    // Only exact pinned endpoint bindings from the original record can be
    // used. A changed advertisement/port has no automatic recovery route.
    final sources = <MacMoveRouter>[];
    for (final binding in record.routerBindings) {
      final endpoint = _endpoints[binding];
      if (endpoint == null) {
        throw const MoveExecutionFailure('recovery_binding_mismatch');
      }
      sources.add(endpoint);
    }
    final target = _endpoints[record.targetRouterBinding];
    if (target == null) {
      throw const MoveExecutionFailure('recovery_binding_mismatch');
    }
    final request = MacMoveRequest(
      operationId: record.operationId,
      reviewId: record.operationId,
      sourceDataset: _recoverySource!,
      targetDataset: _recoveryTarget!,
      sourceGeneration: _sourceGeneration,
      targetGeneration: _targetGeneration,
      sessionId: _sessionId!,
      discoveryRevision: _discoveryRevision!,
      connectivityRevision: record.operationId,
      sources: sources,
      target: target,
      inventoryAttestation: record.operationId,
    );
    final result = await _run(request.encode('observe', lifecycleDirectory,
        fencedAtMs: record.fencedAt.millisecondsSinceEpoch));
    _requireEvidence(result, record.operationId);
    MoveRouterObservation row(Object? value) {
      if (value is! Map<String, dynamic>) throw const FormatException();
      return MoveRouterObservation(
        binding: _commitment(value['binding']),
        datasetCommitment: _commitment(value['dataset_commitment']),
        checkedAt: _time(value['checked_at_ms']),
        authenticated: value['authenticated'] == true,
        pendingEmpty: value['pending_empty'] == true,
        fullMatch: value['full_match'] == true,
        connectivityVerified: false,
      );
    }

    final rows = result['sources'];
    if (rows is! List || rows.length != sources.length) {
      throw const FormatException();
    }
    return MoveObservation(
      operationId: record.operationId,
      recoveryBindingVerified: result['recovery_binding_verified'] == true &&
          result['source_commitment'] == record.sourceCommitment &&
          result['target_commitment'] == record.targetCommitment,
      workerTerminated: result['worker_terminated'] == true,
      sources: rows.map(row).toList(growable: false),
      target: row(result['target']),
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
      final output = <int>[];
      var stderrBytes = 0;
      final outDone = process.stdout.listen((chunk) {
        if (output.length + chunk.length > 16384) {
          invalid = true;
          process.kill(ProcessSignal.sigkill);
        } else {
          output.addAll(chunk);
        }
      }).asFuture<void>();
      final errDone = process.stderr.listen((chunk) {
        stderrBytes += chunk.length;
        if (stderrBytes > 16384) {
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
      final exitCode = await process.exitCode;
      await Future.wait([outDone, errDone]);
      if (invalid || exitCode != 0) throw const FormatException();
      final result = jsonDecode(utf8.decode(output));
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
        result['profile_id'] != macMoveProfile ||
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
    final rows = value.map(_commitment).toList(growable: false);
    if (rows.toSet().length != rows.length) throw const FormatException();
    return rows;
  }
}
