/// Pure assessment for one border router joining one selected Thread network.
/// Identifiers stay in memory and must never enter a persisted operation record.
enum SourceState { vendorAttestedUncommissioned, verifiedExisting, unknown }

enum DeviceCapability { supported, unsupported, unknown }

enum ThreadReadiness { ready, disabled, unknown }

enum PendingState { empty, present, error, unknown }

enum JoinDecision {
  readyForLabReview,
  alreadyJoined,
  needsEvidence,
  unavailable
}

enum JoinReason {
  unsupportedDevice,
  threadDisabled,
  unknownCapability,
  missingAuthority,
  unverifiedSource,
  sourceMayHaveAccessories,
  staleTarget,
  targetMismatch,
  pendingUpdate,
  unknownPending,
  staleRouter,
  invalidRouterSelection,
}

class NetworkRead {
  const NetworkRead({
    required this.routerId,
    required this.identity,
    required this.checkedAt,
    required this.authenticated,
    required this.activeRead,
    required this.pending,
  });

  final String routerId;
  final String identity;
  final DateTime checkedAt;
  final bool authenticated;
  final bool activeRead;
  final PendingState pending;

  bool freshAt(DateTime now, Duration maxAge) =>
      !checkedAt.isAfter(now) && now.difference(checkedAt) <= maxAge;
}

class JoinCandidate {
  const JoinCandidate({
    required this.routerId,
    required this.targetIdentity,
    required this.model,
    required this.firmware,
    required this.capability,
    required this.threadReadiness,
    required this.authorizedTargetCredentials,
    required this.authorizedDeviceCommand,
    required this.sourceState,
    required this.emptySourceAttested,
    required this.targetRead,
    this.routerRead,
  });

  final String routerId;
  final String targetIdentity;
  final String model;
  final String firmware;
  final DeviceCapability capability;
  final ThreadReadiness threadReadiness;
  final bool authorizedTargetCredentials;
  final bool authorizedDeviceCommand;
  final SourceState sourceState;

  /// Operator evidence about the *controlled source*, never inferred from scan.
  final bool emptySourceAttested;
  final NetworkRead targetRead;
  final NetworkRead? routerRead;
}

class JoinAssessment {
  const JoinAssessment(this.decision, this.reasons);
  final JoinDecision decision;
  final List<JoinReason> reasons;
}

JoinAssessment assessJoin(JoinCandidate c, DateTime now,
    {Duration maxReadAge = const Duration(minutes: 5)}) {
  final targetValid = c.targetIdentity.isNotEmpty &&
      c.targetRead.routerId.isNotEmpty &&
      c.targetRead.identity == c.targetIdentity &&
      c.targetRead.freshAt(now, maxReadAge) &&
      c.targetRead.authenticated &&
      c.targetRead.activeRead;
  final router = c.routerRead;
  final routerValid = router != null &&
      c.routerId.isNotEmpty &&
      router.routerId == c.routerId &&
      router.identity.isNotEmpty &&
      router.freshAt(now, maxReadAge) &&
      router.authenticated &&
      router.activeRead;

  // This is a read-only no-op finding, so mutation support, authority, source
  // inventory and Thread readiness are irrelevant. Pending status is disclosed.
  if (targetValid && routerValid && router.identity == c.targetIdentity) {
    final warnings = <JoinReason>[];
    for (final read in [c.targetRead, router]) {
      if (read.pending == PendingState.present) {
        warnings.add(JoinReason.pendingUpdate);
      } else if (read.pending != PendingState.empty) {
        warnings.add(JoinReason.unknownPending);
      }
    }
    return JoinAssessment(JoinDecision.alreadyJoined,
        List<JoinReason>.unmodifiable(warnings.toSet()));
  }

  final reasons = <JoinReason>[];
  if (c.routerId.isEmpty ||
      c.targetRead.routerId.isEmpty ||
      c.routerId == c.targetRead.routerId) {
    reasons.add(JoinReason.invalidRouterSelection);
  }
  if (c.capability == DeviceCapability.unsupported) {
    reasons.add(JoinReason.unsupportedDevice);
  } else if (c.capability == DeviceCapability.unknown ||
      c.model.isEmpty ||
      c.firmware.isEmpty) {
    reasons.add(JoinReason.unknownCapability);
  }
  if (c.threadReadiness == ThreadReadiness.disabled) {
    reasons.add(JoinReason.threadDisabled);
  } else if (c.threadReadiness == ThreadReadiness.unknown) {
    reasons.add(JoinReason.unknownCapability);
  }
  if (!c.authorizedTargetCredentials || !c.authorizedDeviceCommand) {
    reasons.add(JoinReason.missingAuthority);
  }
  if (c.sourceState == SourceState.unknown ||
      (c.sourceState == SourceState.vendorAttestedUncommissioned &&
          c.routerRead != null)) {
    reasons.add(JoinReason.unverifiedSource);
  }
  if (!c.emptySourceAttested) reasons.add(JoinReason.sourceMayHaveAccessories);
  if (c.targetIdentity.isEmpty ||
      c.targetRead.routerId.isEmpty ||
      !c.targetRead.freshAt(now, maxReadAge) ||
      !c.targetRead.authenticated ||
      !c.targetRead.activeRead) {
    reasons.add(JoinReason.staleTarget);
  } else if (c.targetRead.identity != c.targetIdentity) {
    reasons.add(JoinReason.targetMismatch);
  }
  if (c.targetRead.pending == PendingState.present) {
    reasons.add(JoinReason.pendingUpdate);
  } else if (c.targetRead.pending != PendingState.empty) {
    reasons.add(JoinReason.unknownPending);
  }
  if (c.sourceState == SourceState.verifiedExisting) {
    if (!routerValid) {
      reasons.add(JoinReason.staleRouter);
    } else if (router.pending == PendingState.present) {
      reasons.add(JoinReason.pendingUpdate);
    } else if (router.pending != PendingState.empty) {
      reasons.add(JoinReason.unknownPending);
    }
  }
  final unique = List<JoinReason>.unmodifiable(reasons.toSet());
  if (unique.contains(JoinReason.unsupportedDevice) ||
      unique.contains(JoinReason.threadDisabled)) {
    return JoinAssessment(JoinDecision.unavailable, unique);
  }
  if (unique.isNotEmpty) {
    return JoinAssessment(JoinDecision.needsEvidence, unique);
  }
  return const JoinAssessment(JoinDecision.readyForLabReview, []);
}
