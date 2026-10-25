import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/join/join_assessment.dart';

void main() {
  final now = DateTime.utc(2026, 10, 25, 12);
  NetworkRead read(String router, String identity, {PendingState pending = PendingState.empty,
      DateTime? checkedAt, bool authenticated = true}) => NetworkRead(
        routerId: router, identity: identity,
        checkedAt: checkedAt ?? now.subtract(const Duration(seconds: 30)),
        authenticated: authenticated, activeRead: true, pending: pending);
  JoinCandidate candidate({
    String targetIdentity = 'target-id', String readIdentity = 'target-id',
    SourceState source = SourceState.vendorAttestedUncommissioned,
    NetworkRead? sourceRead, bool empty = true,
    DeviceCapability capability = DeviceCapability.supported,
    ThreadReadiness readiness = ThreadReadiness.ready,
    PendingState targetPending = PendingState.empty,
    DateTime? targetAt, String routerId = 'router-A',
    String targetRouterId = 'target-router', bool commandAuthority = true,
  }) => JoinCandidate(
        routerId: routerId, targetIdentity: targetIdentity,
        model: 'Lab Router', firmware: '1.0', capability: capability,
        threadReadiness: readiness, authorizedTargetCredentials: true,
        authorizedDeviceCommand: commandAuthority, sourceState: source,
        emptySourceAttested: empty, routerRead: sourceRead,
        targetRead: read(targetRouterId, readIdentity,
            pending: targetPending, checkedAt: targetAt));

  test('controlled uncommissioned empty source can reach lab review only', () {
    expect(assessJoin(candidate(), now).decision, JoinDecision.readyForLabReview);
    expect(assessJoin(candidate(empty: false), now).decision,
        JoinDecision.needsEvidence);
  });
  test('identity mismatch and stale target never become ready', () {
    expect(assessJoin(candidate(readIdentity: 'another-id'), now).reasons,
        contains(JoinReason.targetMismatch));
    expect(assessJoin(candidate(targetAt: now.subtract(const Duration(minutes: 6))), now).reasons,
        contains(JoinReason.staleTarget));
    expect(assessJoin(candidate(targetAt: now.add(const Duration(seconds: 1))), now).reasons,
        contains(JoinReason.staleTarget));
  });
  test('pending present or failed prevents a plan', () {
    expect(assessJoin(candidate(targetPending: PendingState.present), now).reasons,
        contains(JoinReason.pendingUpdate));
    expect(assessJoin(candidate(targetPending: PendingState.error), now).reasons,
        contains(JoinReason.unknownPending));
  });
  test('unsupported or disabled router is unavailable', () {
    expect(assessJoin(candidate(capability: DeviceCapability.unsupported), now).decision,
        JoinDecision.unavailable);
    expect(assessJoin(candidate(readiness: ThreadReadiness.disabled), now).decision,
        JoinDecision.unavailable);
    expect(assessJoin(candidate(capability: DeviceCapability.unknown), now).decision,
        JoinDecision.needsEvidence);
  });
  test('existing source requires same-router read and empty attestation', () {
    expect(assessJoin(candidate(source: SourceState.verifiedExisting), now).reasons,
        contains(JoinReason.staleRouter));
    expect(assessJoin(candidate(source: SourceState.verifiedExisting,
        sourceRead: read('different-router', 'source-id')), now).reasons,
        contains(JoinReason.staleRouter));
    expect(assessJoin(candidate(source: SourceState.verifiedExisting,
        sourceRead: read('router-A', 'source-id'), empty: false), now).reasons,
        contains(JoinReason.sourceMayHaveAccessories));
  });

  test('ready action requires different nonempty source and target routers', () {
    expect(assessJoin(candidate(routerId: ''), now).reasons,
        contains(JoinReason.invalidRouterSelection));
    expect(assessJoin(candidate(targetRouterId: ''), now).reasons,
        contains(JoinReason.invalidRouterSelection));
    expect(assessJoin(candidate(targetRouterId: 'router-A'), now).reasons,
        contains(JoinReason.invalidRouterSelection));
  });
  test('already joined is no-op despite nonempty source and no mutation authority', () {
    final result = assessJoin(candidate(source: SourceState.unknown,
        sourceRead: read('router-A', 'target-id', pending: PendingState.present),
        empty: false, capability: DeviceCapability.unsupported,
        readiness: ThreadReadiness.disabled, commandAuthority: false), now);
    expect(result.decision, JoinDecision.alreadyJoined);
    expect(result.reasons, contains(JoinReason.pendingUpdate));
    expect(result.reasons, isNot(contains(JoinReason.missingAuthority)));
  });
  test('fresh already-joined router yields no join action', () {
    expect(assessJoin(candidate(source: SourceState.verifiedExisting,
        sourceRead: read('router-A', 'target-id')), now).decision,
        JoinDecision.alreadyJoined);
  });
}
