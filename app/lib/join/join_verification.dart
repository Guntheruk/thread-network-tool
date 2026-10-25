import 'join_assessment.dart';

enum AccessoryEvidenceKind { noneAttested, operationalReads, unknown, failed }

enum VerificationOutcome { complete, pending, needsAttention }

class AccessoryOperationalRead {
  const AccessoryOperationalRead(this.subjectId, this.checkedAt,
      {this.operational = true});
  final String subjectId;
  final DateTime checkedAt;
  final bool operational;
}

class AccessoryEvidence {
  const AccessoryEvidence._(this.kind, this.reads);
  static const noneAttested =
      AccessoryEvidence._(AccessoryEvidenceKind.noneAttested, []);
  static const unknown = AccessoryEvidence._(AccessoryEvidenceKind.unknown, []);
  static const failed = AccessoryEvidence._(AccessoryEvidenceKind.failed, []);
  factory AccessoryEvidence.operationalReads(
          List<AccessoryOperationalRead> reads) =>
      AccessoryEvidence._(AccessoryEvidenceKind.operationalReads,
          List<AccessoryOperationalRead>.unmodifiable(reads));
  final AccessoryEvidenceKind kind;
  final List<AccessoryOperationalRead> reads;
}

class JoinVerification {
  const JoinVerification({
    required this.routerId,
    required this.targetIdentity,
    required this.targetRouterId,
    required this.sentAt,
    required this.routerRead,
    required this.targetRead,
    required this.accessories,
    required this.observationComplete,
    this.affectedAccessoryIds = const [],
  });
  final String routerId;
  final String targetIdentity;
  final String targetRouterId;
  final DateTime sentAt;
  final NetworkRead routerRead;
  final NetworkRead targetRead;
  final AccessoryEvidence accessories;
  final List<String> affectedAccessoryIds;

  /// Completion of the observation period defined for this lab device.
  final bool observationComplete;
}

VerificationOutcome verifyJoin(JoinVerification v, DateTime now,
    {Duration maxReadAge = const Duration(minutes: 5)}) {
  bool valid(NetworkRead read, String routerId) =>
      read.routerId == routerId &&
      read.identity == v.targetIdentity &&
      read.checkedAt.isAfter(v.sentAt) &&
      read.freshAt(now, maxReadAge) &&
      read.authenticated &&
      read.activeRead &&
      read.pending == PendingState.empty;
  final subjects = v.affectedAccessoryIds.toSet();
  final reads = v.accessories.reads;
  final accessoryValid = v.accessories.kind ==
          AccessoryEvidenceKind.noneAttested
      ? subjects.isEmpty
      : v.accessories.kind == AccessoryEvidenceKind.operationalReads &&
          subjects.isNotEmpty &&
          subjects.length == v.affectedAccessoryIds.length &&
          reads.length == subjects.length &&
          reads.map((read) => read.subjectId).toSet().length == reads.length &&
          reads.every((read) =>
              subjects.contains(read.subjectId) &&
              read.subjectId.isNotEmpty &&
              read.operational &&
              read.checkedAt.isAfter(v.sentAt) &&
              !read.checkedAt.isAfter(now) &&
              now.difference(read.checkedAt) <= maxReadAge);
  if (v.routerId.isEmpty ||
      v.targetIdentity.isEmpty ||
      v.targetRouterId.isEmpty ||
      v.targetRouterId == v.routerId ||
      !valid(v.routerRead, v.routerId) ||
      !valid(v.targetRead, v.targetRouterId) ||
      !accessoryValid) {
    return VerificationOutcome.needsAttention;
  }
  if (!v.observationComplete) return VerificationOutcome.pending;
  return VerificationOutcome.complete;
}
