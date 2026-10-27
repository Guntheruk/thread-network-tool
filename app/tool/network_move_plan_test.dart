import 'dart:convert';

import 'package:thread_network_tool/native/session.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

Future<void> main() async {
  var instant = DateTime.utc(2026, 10, 25, 12);
  final calls = <String>[];
  final replies = <String, Map<String, dynamic>>{};
  const sourceXpan = '1111111111111111';
  const targetXpan = '2222222222222222';
  const sourceStamp = '0000000000000011';
  const targetStamp = '0000000000000022';

  Map<String, dynamic> reply(String name, String xpan, String stamp) => {
        'schema_version': 1,
        'probe_status': 'completed',
        'authenticated': true,
        'identity_match': 'match',
        'active_status': 'read',
        'pending_status': 'empty',
        'active_network_name': name,
        'active_extended_pan_id': xpan,
        'active_channel': 15,
        'active_timestamp': stamp,
        'network_key': 'never-leak',
      };
  for (final ip in ['192.168.5.11', '192.168.5.12']) {
    replies['aa:$ip'] = reply('SourceNet', sourceXpan, sourceStamp);
  }
  replies['bb:192.168.5.13'] = reply('TargetNet', targetXpan, targetStamp);
  var hideSecondSourceAdvertisement = false;
  Future<NativeReply> native(List<String> arguments, String? credential) async {
    calls.add(arguments.first);
    check({'inspect', 'discover', 'probe'}.contains(arguments.first),
        'unexpected native mutation');
    switch (arguments.first) {
      case 'inspect':
        check({'aa', 'bb'}.contains(credential), 'wrong inspect credential');
        return NativeReply(0, {
          'schema_version': 1,
          'valid': true,
          'network_name': credential == 'aa' ? 'SourceNet' : 'TargetNet',
          'extended_pan_id': credential == 'aa' ? sourceXpan : targetXpan,
          'channel': 15,
          'active_timestamp': credential == 'aa' ? sourceStamp : targetStamp,
        });
      case 'discover':
        return NativeReply(0, {
          'schema_version': 1,
          'discovery_status': 'completed',
          'routers': [
            {
              'service_name': 'Source A',
              'network_name': 'SourceNet',
              'extended_pan_id': sourceXpan,
              'address': '192.168.5.11',
              'port': 10011
            },
            {
              'service_name': 'Source B',
              'network_name':
                  hideSecondSourceAdvertisement ? 'Unclassified' : 'SourceNet',
              'extended_pan_id':
                  hideSecondSourceAdvertisement ? null : sourceXpan,
              'address': '192.168.5.12',
              'port': 10012
            },
            {
              'service_name': 'Target',
              'network_name': 'TargetNet',
              'extended_pan_id': targetXpan,
              'address': '192.168.5.13',
              'port': 10013
            },
          ],
        });
      case 'probe':
        final result = replies['$credential:${arguments[1]}'];
        check(result != null, 'wrong role or endpoint');
        return NativeReply(0, result!);
    }
    throw StateError('unreachable');
  }

  final session = LiveSession(native, now: () => instant);

  Map<String, dynamic> request(String targetId, {DateTime? attestedAt}) => {
        'target_router_id': targetId,
        'delay_seconds': 1800,
        'empty_source_attestation': {
          'method': 'operator_controlled_inventory',
          'scope': 'whole_source_network',
          'attested_at': (attestedAt ?? instant).toIso8601String(),
        },
      };

  await session.perform('discover', {});
  final ids =
      (session.state['routers'] as List).map((r) => r['id'] as String).toList();
  await session.perform('credentials', {'dataset': 'aa'});
  var plan = await session.perform('network-move/plan', request(ids[2]));
  check(
      plan['decision'] == 'needs_evidence' &&
          (plan['blockers'] as List).contains('source_credentials_required'),
      'inspection slot fed planner');

  await session.perform('credentials', {'role': 'source', 'dataset': 'aa'});
  await session.perform('credentials', {'role': 'target', 'dataset': 'bb'});
  await session.perform('credentials', {'dataset': 'aa'});
  plan = await session.perform('network-move/plan', request(ids[2]));
  check(
      (plan['source_routers'] as List).length == 2 &&
          (plan['blockers'] as List).contains('source_read_missing_or_stale'),
      'candidate census or missing-read gate failed');
  for (final id in ids.take(2)) {
    await session.perform('probe', {'role': 'source', 'router_id': id});
  }
  await session.perform('probe', {'role': 'target', 'router_id': ids[2]});
  plan = await session.perform('network-move/plan', request(ids[2]));
  check(plan['decision'] == 'ready_for_lab_review', 'valid read plan blocked');
  check(
      plan['affected_scope'] == 'whole_source_network' &&
          plan['unknown_offline_devices'] == true &&
          plan['inventory_complete'] == false &&
          (plan['source_routers'] as List).length == 2,
      'scope or inventory disclaimer missing');
  final encoded = jsonEncode({'state': session.state, 'plan': plan});
  for (final secret in [
    'aa',
    'bb',
    sourceXpan,
    targetXpan,
    sourceStamp,
    targetStamp,
    '192.168.5.11',
    'never-leak'
  ]) {
    // Tiny credential fixture strings could appear inside ordinary words.
    if (secret.length > 2) check(!encoded.contains(secret), 'secret leaked');
  }

  replies['aa:192.168.5.11'] = {
    ...reply('SourceNet', sourceXpan, sourceStamp),
    'pending_status': 'present',
  };
  await session.perform('probe', {'router_id': ids[0]});
  check(session.currentReview == null,
      'inspection-only probe retained contradictory ready review');
  plan = await session.perform('network-move/plan', request(ids[2]));
  check((plan['blockers'] as List).contains('source_read_missing_or_stale'),
      'generic probe reused stale source-role evidence');
  replies['aa:192.168.5.11'] = reply('SourceNet', sourceXpan, sourceStamp);
  await session.perform('probe', {'role': 'source', 'router_id': ids[0]});
  plan = await session.perform('network-move/plan', request(ids[2]));
  check(plan['decision'] == 'ready_for_lab_review',
      'fresh source-role check did not restore review readiness');
  replies.remove('aa:192.168.5.11');
  try {
    await session.perform('probe', {'role': 'source', 'router_id': ids[0]});
    throw StateError('expected synthetic native failure');
  } on StateError catch (error) {
    check(error.message != 'expected synthetic native failure',
        'synthetic native failure was not raised');
  }
  check(session.currentReview == null, 'throwing probe retained ready review');
  plan = await session.perform('network-move/plan', request(ids[2]));
  check((plan['blockers'] as List).contains('source_read_missing_or_stale'),
      'throwing probe reused stale source-role evidence');
  replies['aa:192.168.5.11'] = reply('SourceNet', sourceXpan, sourceStamp);
  await session.perform('probe', {'role': 'source', 'router_id': ids[0]});

  replies['aa:192.168.5.12'] = {
    ...reply('SourceNet', sourceXpan, sourceStamp),
    'pending_status': 'present',
  };
  await session.perform('probe', {'role': 'source', 'router_id': ids[1]});
  check(session.currentReview == null, 'reprobe retained old review');
  plan = await session.perform('network-move/plan', request(ids[2]));
  check((plan['blockers'] as List).contains('source_pending_not_empty'),
      'one pending source router passed');
  replies['aa:192.168.5.12'] =
      reply('SourceNet', sourceXpan, '0000000000000033');
  await session.perform('probe', {'role': 'source', 'router_id': ids[1]});
  plan = await session.perform('network-move/plan', request(ids[2]));
  check(
      (plan['blockers'] as List).contains('source_timestamp_inconsistent') &&
          (plan['blockers'] as List).contains('source_timestamp_mismatch'),
      'source timestamp drift passed');

  replies['aa:192.168.5.12'] = reply('SourceNet', sourceXpan, sourceStamp);
  await session.perform('probe', {'role': 'source', 'router_id': ids[1]});
  plan = await session.perform(
      'network-move/plan',
      request(ids[2],
          attestedAt: instant.subtract(const Duration(seconds: 1))));
  check((plan['blockers'] as List).contains('empty_source_attestation_stale'),
      'pre-evidence attestation passed');
  plan = await session.perform('network-move/plan', request(ids[2]));
  check(plan['decision'] == 'ready_for_lab_review', 'recovery plan blocked');
  await session.perform('credentials', {'role': 'target', 'dataset': 'aa'});
  check(session.currentReview == null, 'target reimport retained review');
  plan = await session.perform('network-move/plan', request(ids[2]));
  check((plan['blockers'] as List).contains('same_network'),
      'same source and target accepted');
  await session.perform('credentials', {'role': 'target', 'dataset': 'bb'});
  await session.perform('probe', {'role': 'target', 'router_id': ids[2]});
  replies['bb:192.168.5.13'] = {
    ...reply('TargetNet', targetXpan, targetStamp),
    'pending_status': 'present',
  };
  await session.perform('probe', {'role': 'target', 'router_id': ids[2]});
  plan = await session.perform('network-move/plan', request(ids[2]));
  check((plan['blockers'] as List).contains('target_pending_not_empty'),
      'target pending update accepted');
  replies['bb:192.168.5.13'] = {
    ...reply('TargetNet', targetXpan, targetStamp),
    'active_timestamp': null,
  };
  await session.perform('probe', {'role': 'target', 'router_id': ids[2]});
  plan = await session.perform('network-move/plan', request(ids[2]));
  check((plan['blockers'] as List).contains('target_timestamp_unknown'),
      'missing native Active Timestamp accepted');
  replies['bb:192.168.5.13'] = reply('TargetNet', targetXpan, targetStamp);
  await session.perform('probe', {'role': 'target', 'router_id': ids[2]});
  replies['aa:192.168.5.12'] = reply('UnexpectedNet', sourceXpan, sourceStamp);
  await session.perform('probe', {'role': 'source', 'router_id': ids[1]});
  plan = await session.perform('network-move/plan', request(ids[2]));
  check((plan['blockers'] as List).contains('source_identity_unverified'),
      'wrong source identity accepted');
  instant = instant.add(const Duration(minutes: 6));
  check(session.currentReview == null, 'expired review survived');
  plan = await session.perform('network-move/plan', request(ids[2]));
  check(
      (plan['blockers'] as List).contains('source_read_missing_or_stale') &&
          (plan['blockers'] as List).contains('target_read_missing_or_stale'),
      'stale reads passed');
  await session.perform('discover', {});
  check(session.currentReview == null, 'rediscovery retained review');

  // B is identifiable as source only through its authenticated role read.
  // Once identified, a later failed or generic read must not erase it from
  // the source census while the source credential and discovery are unchanged.
  hideSecondSourceAdvertisement = true;
  replies['aa:192.168.5.11'] = reply('SourceNet', sourceXpan, sourceStamp);
  replies['aa:192.168.5.12'] = reply('SourceNet', sourceXpan, sourceStamp);
  replies['bb:192.168.5.13'] = reply('TargetNet', targetXpan, targetStamp);
  final hiddenSession = LiveSession(native, now: () => instant);
  await hiddenSession
      .perform('credentials', {'role': 'source', 'dataset': 'aa'});
  await hiddenSession
      .perform('credentials', {'role': 'target', 'dataset': 'bb'});
  await hiddenSession.perform('credentials', {'dataset': 'aa'});
  await hiddenSession.perform('discover', {});
  final hiddenIds = (hiddenSession.state['routers'] as List)
      .map((r) => r['id'] as String)
      .toList();
  for (final id in hiddenIds.take(2)) {
    await hiddenSession.perform('probe', {'role': 'source', 'router_id': id});
  }
  await hiddenSession
      .perform('probe', {'role': 'target', 'router_id': hiddenIds[2]});
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check(
      plan['decision'] == 'ready_for_lab_review' &&
          (plan['source_routers'] as List).length == 2,
      'authenticated-only source B did not join ready census');
  replies['aa:192.168.5.12'] = {
    ...reply('SourceNet', sourceXpan, sourceStamp),
    'pending_status': 'present',
  };
  await hiddenSession.perform('probe', {'router_id': hiddenIds[1]});
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check(
      (plan['source_routers'] as List).length == 2 &&
          (plan['blockers'] as List).contains('source_read_missing_or_stale'),
      'generic reprobe shrank authenticated source census');
  replies['aa:192.168.5.12'] = reply('SourceNet', sourceXpan, sourceStamp);
  await hiddenSession
      .perform('probe', {'role': 'source', 'router_id': hiddenIds[1]});
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check(plan['decision'] == 'ready_for_lab_review',
      'fresh B role read failed to restore ready review');

  await hiddenSession
      .perform('credentials', {'role': 'target', 'dataset': 'bb'});
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check(
      (plan['source_routers'] as List).length == 2 &&
          (plan['blockers'] as List).contains('target_read_missing_or_stale'),
      'target import erased source membership');
  await hiddenSession
      .perform('probe', {'role': 'target', 'router_id': hiddenIds[2]});
  replies.remove('aa:192.168.5.12');
  try {
    await hiddenSession
        .perform('probe', {'role': 'source', 'router_id': hiddenIds[1]});
    throw StateError('expected synthetic native failure');
  } on StateError catch (error) {
    check(error.message != 'expected synthetic native failure',
        'synthetic native failure was not raised');
  }
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check(
      (plan['source_routers'] as List).length == 2 &&
          (plan['blockers'] as List).contains('source_read_missing_or_stale'),
      'throwing reprobe shrank authenticated source census');
  replies['aa:192.168.5.12'] = reply('SourceNet', sourceXpan, sourceStamp);
  await hiddenSession
      .perform('probe', {'role': 'source', 'router_id': hiddenIds[1]});
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check(plan['decision'] == 'ready_for_lab_review',
      'fresh B role read after failure did not restore readiness');

  await hiddenSession
      .perform('credentials', {'role': 'source', 'dataset': 'aa'});
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check((plan['source_routers'] as List).length == 1,
      'source import retained old membership');
  await hiddenSession
      .perform('probe', {'role': 'source', 'router_id': hiddenIds[1]});
  plan =
      await hiddenSession.perform('network-move/plan', request(hiddenIds[2]));
  check((plan['source_routers'] as List).length == 2,
      'fresh source role read failed to reestablish membership');
  await hiddenSession.perform('discover', {});
  final rediscovered = (hiddenSession.state['routers'] as List)
      .map((r) => r['id'] as String)
      .toList();
  plan = await hiddenSession.perform(
      'network-move/plan', request(rediscovered[2]));
  check((plan['source_routers'] as List).length == 1,
      'rediscovery retained stale authenticated membership');
  check(calls.every((c) => {'inspect', 'discover', 'probe'}.contains(c)),
      'native mutation call occurred');
}
