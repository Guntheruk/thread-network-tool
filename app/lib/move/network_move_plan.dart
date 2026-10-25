/// Pure, read-only assessment of a whole source Thread network.
/// The caller supplies authenticated evidence, not client asserted status flags.
class MoveRead {
  const MoveRead({
    required this.routerId,
    required this.checkedAt,
    required this.matchesRole,
    required this.authenticated,
    required this.completed,
    required this.pendingEmpty,
    required this.activeTimestamp,
  });

  final String routerId;
  final DateTime checkedAt;
  final bool matchesRole;
  final bool authenticated;
  final bool completed;
  final bool pendingEmpty;
  final String? activeTimestamp;

  bool fresh(DateTime now) =>
      !checkedAt.isAfter(now) &&
      now.difference(checkedAt) <= const Duration(minutes: 5);
}

class EmptySourceAttestation {
  const EmptySourceAttestation({
    required this.method,
    required this.scope,
    required this.attestedAt,
  });

  final String method;
  final String scope;
  final DateTime attestedAt;

  bool validAt(DateTime now) =>
      method == 'operator_controlled_inventory' &&
      scope == 'whole_source_network' &&
      !attestedAt.isAfter(now) &&
      now.difference(attestedAt) <= const Duration(minutes: 5);
}

class MoveAssessment {
  const MoveAssessment(this.blockers);
  final List<String> blockers;
  bool get ready => blockers.isEmpty;
}

MoveAssessment assessNetworkMove({
  required DateTime now,
  required bool sourceCredentials,
  required bool targetCredentials,
  required bool distinctIdentities,
  required bool discoveryComplete,
  required List<MoveRead?> sourceReads,
  required MoveRead? targetRead,
  required bool targetIsSource,
  required EmptySourceAttestation? attestation,
  required int delaySeconds,
}) {
  final blockers = <String>{};
  if (!sourceCredentials) blockers.add('source_credentials_required');
  if (!targetCredentials) blockers.add('target_credentials_required');
  if (sourceCredentials && targetCredentials && !distinctIdentities) {
    blockers.add('same_network');
  }
  if (!discoveryComplete) blockers.add('discovery_incomplete');
  if (sourceReads.isEmpty) blockers.add('source_routers_unverified');
  if (targetIsSource) blockers.add('target_is_source');
  if (attestation == null || !attestation.validAt(now)) {
    blockers.add('empty_source_attestation_required');
  }
  if (delaySeconds < 300 || delaySeconds > 86400) {
    blockers.add('invalid_delay');
  }

  String? sourceTimestamp;
  for (final read in sourceReads) {
    if (read == null || !read.fresh(now)) {
      blockers.add('source_read_missing_or_stale');
      continue;
    }
    if (!read.matchesRole || !read.authenticated || !read.completed) {
      blockers.add('source_identity_unverified');
    }
    if (!read.pendingEmpty) blockers.add('source_pending_not_empty');
    if (read.activeTimestamp == null) {
      blockers.add('source_timestamp_unknown');
    } else if (sourceTimestamp == null) {
      sourceTimestamp = read.activeTimestamp;
    } else if (sourceTimestamp != read.activeTimestamp) {
      blockers.add('source_timestamp_inconsistent');
    }
  }
  if (targetRead == null || !targetRead.fresh(now)) {
    blockers.add('target_read_missing_or_stale');
  } else {
    if (!targetRead.matchesRole ||
        !targetRead.authenticated ||
        !targetRead.completed) {
      blockers.add('target_identity_unverified');
    }
    if (!targetRead.pendingEmpty) blockers.add('target_pending_not_empty');
    if (targetRead.activeTimestamp == null) {
      blockers.add('target_timestamp_unknown');
    }
  }
  return MoveAssessment(List.unmodifiable(blockers));
}
