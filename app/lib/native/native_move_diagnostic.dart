/// Fixed, opt-in isolated-test diagnostics. Never includes input values, IDs,
/// commitments, endpoints, datasets, upstream exception strings or labels.
enum NativePreparationStage {
  journal,
  recovery,
  fixtureRefresh,
  nativeProcess,
  nativeResult,
  evidence,
  plan;

  String get wire => switch (this) {
        fixtureRefresh => 'fixture_refresh',
        nativeProcess => 'native_process',
        nativeResult => 'native_result',
        _ => name,
      };
}

const nativePreparationReasons = {
  'journal_failure', 'unresolved_operation', 'fixture_unavailable',
  'worker_failure', 'uncorrelated_native_result', 'native_reason_unknown',
  'invalid_native_evidence', 'execution_unavailable', 'review_expired',
  'invalid_plan',
  // Native fixed reasons, copied from the bounded worker/guard protocol.
  'invalid_request', 'fixture_untrusted', 'connectivity_stale',
  'isolated_network_required', 'fixture_process_missing',
  'fixture_process_invalid', 'fixture_process_replaced',
  'fixture_fd_unavailable', 'fixture_socket_unowned',
  'fixture_socket_ambiguous', 'fixture_duplicate', 'linux_fixture_required',
  'lease_unavailable', 'lifecycle_untrusted', 'lifecycle_unavailable',
  'worker_busy', 'hash_failed', 'binding_mismatch', 'invalid_dataset',
  'unsupported_dataset_fields', 'same_network', 'authorization_incomplete',
  'endpoint_role_conflict', 'duplicate_endpoint', 'invalid_endpoint',
  'timestamp_rollback_without_key_change', 'unsupported_delay',
  'pending_dataset_overflow', 'source_snapshot_changed_or_unavailable',
  'target_snapshot_changed_or_unavailable', 'preflight_deadline',
  'operation_consumed',
};

class NativePreparationDiagnostic {
  const NativePreparationDiagnostic._(this.stage, this.reason);
  final NativePreparationStage stage;
  final String reason;

  factory NativePreparationDiagnostic.fixed(
          NativePreparationStage stage, String reason) =>
      NativePreparationDiagnostic._(
          stage,
          nativePreparationReasons.contains(reason)
              ? reason
              : 'worker_failure');

  factory NativePreparationDiagnostic.nativeRefusal(
      Map<String, dynamic> result, String expectedOperationId) {
    if (result['schema_version'] != 1 ||
        result['operation_id'] != expectedOperationId) {
      return const NativePreparationDiagnostic._(
          NativePreparationStage.nativeResult, 'uncorrelated_native_result');
    }
    final reason = result['reason'];
    return NativePreparationDiagnostic._(
        NativePreparationStage.nativeResult,
        reason is String && nativePreparationReasons.contains(reason)
            ? reason
            : 'native_reason_unknown');
  }

  String get fixtureMarker => 'TNT_APP_PREPARE_FAILURE ${stage.wire} $reason';
}
