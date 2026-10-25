import 'live_api.dart';
import 'native/session.dart';

/// Direct in-process adapter for desktop Flutter. It uses the same bounded
/// native calls and state transitions as the loopback helper, without HTTP.
class NativeLiveApi implements NetworkMoveExecutionApi {
  NativeLiveApi({required NativeCall native, LiveSession? session})
    : _session = session ?? LiveSession(native);

  final LiveSession _session;

  @override
  bool get executionAvailable => _session.executionAvailable;

  @override
  bool get executionRecoveryAvailable => _session.executionRecoveryAvailable;

  Future<Object?> _execution(String action, Map<String, dynamic> body) async {
    try {
      return await _session.perform(action, body);
    } catch (_) {
      throw const LiveApiException();
    }
  }

  @override
  Future<NetworkMoveExecutionReview> prepareExecution(String reviewId) async =>
      NetworkMoveExecutionReview.fromJson(
        await _execution('network-move/execution/prepare', {
          'review_id': reviewId,
        }),
      );

  @override
  Future<NetworkMoveExecutionStatus> confirmExecution(String reviewId) async =>
      NetworkMoveExecutionStatus.fromJson(
        await _execution('network-move/execution/confirm', {
          'review_id': reviewId,
        }),
      );

  @override
  Future<NetworkMoveExecutionStatus?> currentExecution() async {
    final result = await _execution('network-move/execution/current', {});
    if (result is! Map<String, dynamic> || !result.containsKey('status')) {
      throw const LiveApiException();
    }
    return result['status'] == null
        ? null
        : NetworkMoveExecutionStatus.fromJson(result['status']);
  }

  @override
  Future<NetworkMoveExecutionStatus> checkExecution(
    String operationId, {
    bool resume = false,
  }) async => NetworkMoveExecutionStatus.fromJson(
    await _execution('network-move/execution/check', {
      'operation_id': operationId,
      'resume': resume,
    }),
  );

  @override
  Future<NetworkMoveExecutionStatus> stopExecution(String operationId) async =>
      NetworkMoveExecutionStatus.fromJson(
        await _execution('network-move/execution/stop', {
          'operation_id': operationId,
        }),
      );

  Future<LiveState> _perform(String action, Map<String, dynamic> body) async {
    try {
      return LiveState.fromJson(await _session.perform(action, body));
    } catch (_) {
      throw const LiveApiException();
    }
  }

  @override
  Future<LiveState> state() async => LiveState.fromJson(_session.state);

  @override
  Future<LiveState> discover() => _perform('discover', {});

  @override
  Future<LiveState> credentials(String dataset) =>
      _perform('credentials', {'dataset': dataset});

  @override
  Future<LiveState> probe(String routerId) =>
      _perform('probe', {'router_id': routerId});

  @override
  Future<LiveState> credentialsForRole(String role, String dataset) =>
      _perform('credentials', {'role': role, 'dataset': dataset});

  @override
  Future<LiveState> probeForRole(String role, String routerId) =>
      _perform('probe', {'role': role, 'router_id': routerId});

  @override
  Future<NetworkMovePlan> networkMovePlan({
    required String targetRouterId,
    required EmptySourceAttestationInput attestation,
    required int delaySeconds,
  }) async {
    try {
      return NetworkMovePlan.fromJson(
        await _session.perform('network-move/plan', {
          'target_router_id': targetRouterId,
          'empty_source_attestation': attestation.toJson(),
          'delay_seconds': delaySeconds,
        }),
      );
    } catch (_) {
      throw const LiveApiException();
    }
  }

  @override
  Future<NetworkMovePlan?> currentNetworkMovePlan() async {
    final current = _session.currentReview;
    return current == null ? null : NetworkMovePlan.fromJson(current);
  }
}

/// A desktop or phone with no supported native helper remains visibly live
/// unavailable. It never falls back to fictional networks or starts a process.
class UnsupportedLiveApi implements LiveApi {
  const UnsupportedLiveApi();

  static const LiveState _unavailable = LiveState(
    credentialAvailable: false,
    credentialNetworkName: null,
    discoveryStatus: 'unsupported',
    observedAt: null,
    routers: [],
  );

  @override
  Future<LiveState> state() async => _unavailable;

  @override
  Future<LiveState> discover() async => _unavailable;

  @override
  Future<LiveState> credentials(String dataset) async =>
      throw const LiveApiException();

  @override
  Future<LiveState> probe(String routerId) async =>
      throw const LiveApiException();
}
