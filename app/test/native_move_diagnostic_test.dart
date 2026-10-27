import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/native/native_move_diagnostic.dart';

void main() {
  final operation = 'a' * 64;
  test('native refusal preserves only a correlated fixed reason', () {
    final diagnostic = NativePreparationDiagnostic.nativeRefusal({
      'schema_version': 1,
      'operation_id': operation,
      'reason': 'source_snapshot_changed_or_unavailable',
      'source_dataset': 'synthetic-secret-dataset',
      'endpoint': 'synthetic-private-endpoint',
    }, operation);
    expect(diagnostic.fixtureMarker,
        'TNT_APP_PREPARE_FAILURE native_result source_snapshot_changed_or_unavailable');
    expect(diagnostic.fixtureMarker.contains(operation), isFalse);
    expect(diagnostic.fixtureMarker.contains('synthetic'), isFalse);
  });
  test('mismatched operation cannot attribute even a known native reason', () {
    final diagnostic = NativePreparationDiagnostic.nativeRefusal({
      'schema_version': 1,
      'operation_id': 'b' * 64,
      'reason': 'source_snapshot_changed_or_unavailable',
    }, operation);
    expect(diagnostic.reason, 'uncorrelated_native_result');
  });
  test('unknown native text and malformed schema never become diagnostics', () {
    for (final reason in ['raw-private-label-or-error', 123, null]) {
      final diagnostic = NativePreparationDiagnostic.nativeRefusal({
        'schema_version': 1,
        'operation_id': operation,
        'reason': reason,
      }, operation);
      expect(diagnostic.reason, 'native_reason_unknown');
      expect(diagnostic.fixtureMarker.contains('raw-private'), isFalse);
    }
    expect(
        NativePreparationDiagnostic.nativeRefusal({
          'schema_version': 2,
          'operation_id': operation,
          'reason': 'invalid_request',
        }, operation)
            .reason,
        'uncorrelated_native_result');
  });
  test('app failure stages cannot emit arbitrary reason text', () {
    expect(
        NativePreparationDiagnostic.fixed(
          NativePreparationStage.fixtureRefresh,
          'private exception text',
        ).fixtureMarker,
        'TNT_APP_PREPARE_FAILURE fixture_refresh worker_failure');
  });
}
