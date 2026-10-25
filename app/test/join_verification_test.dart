import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/join/join_assessment.dart';
import 'package:thread_network_tool/join/join_verification.dart';

void main() {
  final sent = DateTime.utc(2026, 10, 25, 12);
  final now = sent.add(const Duration(minutes: 2));
  NetworkRead read(String router, String identity,
          {DateTime? at,
          bool authenticated = true,
          PendingState pending = PendingState.empty}) =>
      NetworkRead(
          routerId: router,
          identity: identity,
          checkedAt: at ?? now.subtract(const Duration(seconds: 10)),
          authenticated: authenticated,
          activeRead: true,
          pending: pending);
  JoinVerification evidence(
          {NetworkRead? router,
          NetworkRead? target,
          AccessoryEvidence accessories = AccessoryEvidence.noneAttested,
          bool observed = true}) =>
      JoinVerification(
          routerId: 'router-A',
          targetIdentity: 'target-id',
          targetRouterId: 'target-router',
          sentAt: sent,
          routerRead: router ?? read('router-A', 'target-id'),
          targetRead: target ?? read('target-router', 'target-id'),
          accessories: accessories,
          observationComplete: observed);

  test('same router and target must have fresh authenticated matching reads',
      () {
    expect(verifyJoin(evidence(), now), VerificationOutcome.complete);
    expect(verifyJoin(evidence(router: read('router-B', 'target-id')), now),
        VerificationOutcome.needsAttention);
    expect(verifyJoin(evidence(router: read('router-A', 'old-id')), now),
        VerificationOutcome.needsAttention);
    expect(verifyJoin(evidence(target: read('target-router', 'other-id')), now),
        VerificationOutcome.needsAttention);
    expect(
        verifyJoin(
            evidence(router: read('router-A', 'target-id', at: sent)), now),
        VerificationOutcome.needsAttention);
    expect(
        verifyJoin(
            evidence(
                target:
                    read('target-router', 'target-id', authenticated: false)),
            now),
        VerificationOutcome.needsAttention);
  });
  test('pending updates, unknown accessories, and incomplete observation fail',
      () {
    expect(
        verifyJoin(
            evidence(
                router: read('router-A', 'target-id',
                    pending: PendingState.present)),
            now),
        VerificationOutcome.needsAttention);
    expect(verifyJoin(evidence(accessories: AccessoryEvidence.unknown), now),
        VerificationOutcome.needsAttention);
    expect(verifyJoin(evidence(observed: false), now),
        VerificationOutcome.pending);
  });
  test('interim old identity, pending update, and unknown accessories wait',
      () {
    expect(
        verifyJoin(
            evidence(router: read('router-A', 'old-id'), observed: false), now),
        VerificationOutcome.pending);
    expect(
        verifyJoin(
            evidence(
                router: read('router-A', 'target-id',
                    pending: PendingState.present),
                observed: false),
            now),
        VerificationOutcome.pending);
    expect(
        verifyJoin(
            evidence(accessories: AccessoryEvidence.unknown, observed: false),
            now),
        VerificationOutcome.pending);
    expect(
        verifyJoin(
            evidence(
                router: read('wrong-router', 'target-id'), observed: false),
            now),
        VerificationOutcome.needsAttention);
    final wrongAccessory = JoinVerification(
        routerId: 'router-A',
        targetIdentity: 'target-id',
        targetRouterId: 'target-router',
        sentAt: sent,
        routerRead: read('router-A', 'target-id'),
        targetRead: read('target-router', 'target-id'),
        affectedAccessoryIds: const ['accessory-A'],
        accessories: AccessoryEvidence.operationalReads([
          AccessoryOperationalRead('accessory-B', now),
        ]),
        observationComplete: false);
    expect(verifyJoin(wrongAccessory, now), VerificationOutcome.needsAttention);
  });
  test('operational accessory reads must identify every subject after dispatch',
      () {
    final stale = JoinVerification(
        routerId: 'router-A',
        targetIdentity: 'target-id',
        targetRouterId: 'target-router',
        sentAt: sent,
        routerRead: read('router-A', 'target-id'),
        targetRead: read('target-router', 'target-id'),
        affectedAccessoryIds: const ['accessory-A'],
        accessories: AccessoryEvidence.operationalReads([
          AccessoryOperationalRead('accessory-A', sent),
        ]),
        observationComplete: true);
    expect(verifyJoin(stale, now), VerificationOutcome.needsAttention);
    JoinVerification withReads(List<AccessoryOperationalRead> reads) =>
        JoinVerification(
            routerId: 'router-A',
            targetIdentity: 'target-id',
            targetRouterId: 'target-router',
            sentAt: sent,
            routerRead: read('router-A', 'target-id'),
            targetRead: read('target-router', 'target-id'),
            affectedAccessoryIds: const ['accessory-A'],
            accessories: AccessoryEvidence.operationalReads(reads),
            observationComplete: true);
    expect(
        verifyJoin(
            withReads([
              AccessoryOperationalRead('other-accessory', now),
            ]),
            now),
        VerificationOutcome.needsAttention);
    expect(
        verifyJoin(
            withReads([
              AccessoryOperationalRead('accessory-A', now),
            ]),
            now),
        VerificationOutcome.complete);
  });
}
