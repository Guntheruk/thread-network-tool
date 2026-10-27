import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/live_api.dart';

void main() {
  test('Mac configuration result has a distinct profile and terminal stage',
      () {
    final review = NetworkMoveExecutionReview.fromJson({
      'schema_version': 1,
      'mode': 'network_move_execution_review',
      'review_id': 'r',
      'operation_id': 'o',
      'profile_id': 'eero-source-network-alpha-v1',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 1))
          .toIso8601String(),
      'source_router_ids': ['s'],
      'target_router_id': 't',
      'delay_seconds': 300,
      'observation_seconds': 30,
    });
    expect(review.profileId, 'eero-source-network-alpha-v1');
    final status = NetworkMoveExecutionStatus.fromJson({
      'schema_version': 1,
      'mode': 'network_move_execution_status',
      'operation_id': 'o',
      'profile_id': 'eero-source-network-alpha-v1',
      'stage': 'verified_configuration',
      'disposition': 'accepted',
      'reason': 'configuration_verified',
    });
    expect(status.terminal, isTrue);
  });
}
