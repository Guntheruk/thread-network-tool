import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/live_api.dart';
import 'package:thread_network_tool/move/native_move_journal.dart';
import 'package:thread_network_tool/native/mac_move_adapter.dart';
import 'package:thread_network_tool/native/session.dart';
import 'package:thread_network_tool/native_live_api.dart';

const _sourceName = 'LabSource';
const _targetName = 'LabTarget';
const _sourceXpan = '1111111111111111';
const _targetXpan = '2222222222222222';
const _stamp = '0000000000010000';
const _journalHelper =
    '/Users/richard/thread-alpha-worktrees/integration/build/profile-checks/thread-move-journal';

String _dataset(String name, String xpan, int channel) {
  final nameBytes = utf8.encode(name);
  String hex(Iterable<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '00030000${channel.toRadixString(16).padLeft(2, '0')}'
      '0208$xpan'
      '03${nameBytes.length.toRadixString(16).padLeft(2, '0')}${hex(nameBytes)}'
      '010212340510000102030405060708090a0b0c0d0e0f'
      '0410101112131415161718191a1b1c1d1e1f'
      '0e08$_stamp';
}

final _sourceDataset = _dataset(_sourceName, _sourceXpan, 15);
final _targetDataset = _dataset(_targetName, _targetXpan, 20);

/// Synthetic read replies stay in process. No socket or household endpoint is
/// opened; only the fake worker and real local journal are child processes.
class _ReadFixture {
  bool changedSourceEndpoint = false;

  Future<NativeReply> call(List<String> args, String? credential) async {
    if (args.first == 'inspect') {
      final source = credential == _sourceDataset;
      expect(credential, anyOf(_sourceDataset, _targetDataset));
      return NativeReply(0, {
        'schema_version': 1,
        'valid': true,
        'network_name': source ? _sourceName : _targetName,
        'extended_pan_id': source ? _sourceXpan : _targetXpan,
        'channel': source ? 15 : 20,
        'active_timestamp': _stamp,
      });
    }
    if (args.first == 'discover') {
      expect(credential, isNull);
      return NativeReply(0, {
        'schema_version': 1,
        'discovery_status': 'completed',
        'routers': [
          {
            'service_name': 'Source Eero A',
            'network_name': _sourceName,
            'extended_pan_id': _sourceXpan,
            'address': '192.168.40.11',
            'port': changedSourceEndpoint ? 49114 : 49111,
          },
          {
            'service_name': 'Source Eero B',
            'network_name': _sourceName,
            'extended_pan_id': _sourceXpan,
            'address': '192.168.40.12',
            'port': 49112,
          },
          {
            'service_name': 'Target router',
            'network_name': _targetName,
            'extended_pan_id': _targetXpan,
            'address': '192.168.40.13',
            'port': 49113,
          },
        ],
      });
    }
    expect(args.first, 'probe');
    expect(args, hasLength(3));
    final source = args[1] != '192.168.40.13';
    expect(credential, source ? _sourceDataset : _targetDataset);
    return NativeReply(0, {
      'schema_version': 1,
      'probe_status': 'completed',
      'authenticated': true,
      'identity_match': 'match',
      'active_status': 'read',
      'pending_status': 'empty',
      'active_network_name': source ? _sourceName : _targetName,
      'active_extended_pan_id': source ? _sourceXpan : _targetXpan,
      'active_channel': source ? 15 : 20,
      'active_timestamp': _stamp,
    });
  }
}

class _Harness {
  _Harness(this.root);
  final Directory root;
  late final File worker = File('${root.path}/fake-worker');
  String get journalDirectory => '${root.path}/move-journal';
  File get events => File('${root.path}/events');
  File get uncertainMarker => File('${root.path}/uncertain');

  Future<void> initialize() async {
    await worker.writeAsString('''#!/usr/bin/env python3
import hashlib, json, os, subprocess, sys, time
base = os.path.dirname(__file__)
lines = sys.stdin.read().splitlines()
assert lines[0] == 'TNT-MAC-MOVE/1' and lines[-1] == 'END'
i = 1
def field(name):
    global i
    prefix = name + ' '
    assert lines[i].startswith(prefix), (name, lines[i])
    value = lines[i][len(prefix):]
    i += 1
    return value
mode = field('mode')
operation = field('operation_id')
review = field('review_revision')
sg = field('source_generation')
tg = field('target_generation')
session = field('session_id')
discovery = field('discovery_revision')
connectivity = field('connectivity_revision')
source_raw = bytes.fromhex(field('source_dataset'))
target_raw = bytes.fromhex(field('target_dataset'))
count = int(field('source_count'))
assert 1 <= count <= 8
sources = [field('source_router').split(' ') for _ in range(count)]
target = field('target_router').split(' ')
delay = field('delay_ms')
inventory = field('inventory_attestation')
assert field('controlled_empty') == 'yes'
assert field('manual_recovery') == 'yes'
journal = field('lifecycle_directory')
fenced = field('fenced_at_ms')
expected = field('expected_binding')
assert i == len(lines) - 1
assert delay == '300000' and all(len(row) == 3 for row in sources + [target])
def digest(value): return hashlib.sha256(value).hexdigest()
def canonical(raw):
    fields = {}
    at = 0
    while at < len(raw):
        typ, size = raw[at], raw[at + 1]
        fields[typ] = raw[at + 2:at + 2 + size]
        at += 2 + size
    assert at == len(raw) and len(fields) == 7
    return b''.join(bytes((typ, len(value))) + value for typ, value in sorted(fields.items()))
source_hash, target_hash = digest(canonical(source_raw)), digest(canonical(target_raw))
def line(row): return '\\n'.join(row) + '\\n'
def router_hash(row): return digest(('TNT-MAC-ROUTER/1\\n' + line(row)).encode())
bindings = [router_hash(row) for row in sources]
router_lines = sorted(line(row) for row in sources)
full_binding = 'TNT-MAC-MOVE-BINDING/1\\n' + '\\n'.join((operation, review, sg, tg, session, discovery, connectivity, inventory, source_hash, target_hash)) + '\\n' + ''.join(router_lines) + line(target) + delay + '\\n'
binding = digest(full_binding.encode())
assert expected == '-' or expected == binding
with open(os.path.join(base, 'events'), 'a', encoding='utf8') as log:
    log.write(mode + '\\n')
now = int(time.time() * 1000)
result = dict(schema_version=1, operation_id=operation,
              profile_id='eero-source-network-alpha-v1', binding_commitment=binding,
              source_commitment=source_hash, target_commitment=target_hash,
              source_bindings=bindings, target_binding=router_hash(target),
              checked_at_ms=now, profile_verified=True, runtime_verified=True,
              independent_deadline=True)
if mode == 'inspect':
    result.update(ready=True)
elif mode == 'dispatch':
    record = subprocess.check_output([${jsonEncode(_journalHelper)}, 'read', journal], text=True)
    assert 'stage=dispatch_fenced\\n' in record
    assert 'profile=eero-source-network-alpha-v1\\n' in record
    assert 'operation=' + operation + '\\n' in record
    assert 'source=' + source_hash + '\\n' in record
    assert 'target=' + target_hash + '\\n' in record
    assert 'routers=' + ','.join(sorted(bindings)) + '\\n' in record
    assert fenced != '0'
    if os.path.exists(os.path.join(base, 'uncertain')):
        result.update(disposition='uncertain', petitions=1, pending_set_invocations=1)
    else:
        result.update(disposition='accepted', petitions=1, pending_set_invocations=1)
elif mode == 'observe':
    record = subprocess.check_output([${jsonEncode(_journalHelper)}, 'read', journal], text=True)
    assert 'operation=' + operation + '\\n' in record
    assert 'target_router=' + router_hash(target) + '\\n' in record
    def row(binding):
        return dict(binding=binding, dataset_commitment=target_hash, checked_at_ms=now,
                    authenticated=True, pending_empty=True, full_match=True,
                    connectivity_verified=False)
    result.update(worker_terminated=True, recovery_binding_verified=True,
                  sources=[row(binding) for binding in bindings],
                  target=row(router_hash(target)))
else:
    raise AssertionError(mode)
print(json.dumps(result, separators=(',', ':')))
''');
    final chmod = await Process.run('chmod', ['700', worker.path]);
    expect(chmod.exitCode, 0);
  }

  MacMoveAdapter adapter() => MacMoveAdapter(
        workerExecutable: worker.path,
        lifecycleDirectory: journalDirectory,
        journal: NativeMoveJournal(
            executable: _journalHelper, directory: journalDirectory),
      );

  NativeLiveApi api(MacMoveAdapter adapter, {_ReadFixture? fixture}) {
    final read = (fixture ?? _ReadFixture()).call;
    return NativeLiveApi(
      native: read,
      session: LiveSession(read, execution: adapter),
    );
  }

  Future<List<String>> modes() async =>
      events.existsSync() ? await events.readAsLines() : [];
}

Future<(String, List<String>)> _review(NativeLiveApi api,
    {required bool eero, required bool wholeGroup}) async {
  await api.credentialsForRole('source', _sourceDataset);
  await api.credentialsForRole('target', _targetDataset);
  final state = await api.discover();
  expect(state.routers.length, 3);
  final sourceIds = [state.routers[0].id, state.routers[1].id];
  final targetId = state.routers[2].id;
  await api.probeForRole('target', targetId);
  for (final id in sourceIds) {
    await api.probeForRole('source', id);
  }
  final plan = await api.networkMovePlan(
    targetRouterId: targetId,
    attestation: EmptySourceAttestationInput(
      attestedAt: DateTime.now().toUtc(),
      operatorEeroSource: eero,
      allSourceEerosRepresented: wholeGroup,
    ),
    delaySeconds: 300,
  );
  return (plan.reviewId, plan.blockers);
}

void main() {
  test(
      'real Mac journal fences one accepted session dispatch and recovery reads',
      () async {
    expect(Platform.isMacOS, isTrue,
        reason: 'Mac execution test requires macOS');
    expect(File(_journalHelper).existsSync(), isTrue,
        reason: 'Build the explicit native move journal test helper first');
    final root = await Directory.systemTemp.createTemp('tnt-mac-session-');
    final harness = _Harness(root);
    try {
      await harness.initialize();
      final adapter = harness.adapter();
      final api = harness.api(adapter);
      final (blockedReview, blockers) =
          await _review(api, eero: true, wholeGroup: false);
      expect(blockers, contains('source_group_attestation_required'));
      await expectLater(api.prepareExecution(blockedReview),
          throwsA(isA<LiveApiException>()));
      expect(await harness.modes(), isEmpty);

      final (reviewId, readyBlockers) =
          await _review(api, eero: true, wholeGroup: true);
      expect(readyBlockers, isEmpty);
      final review = await api.prepareExecution(reviewId);
      expect(review.profileId, macMoveProfile);
      expect(review.sourceRouterIds, hasLength(2));
      expect(await harness.modes(), ['inspect']);
      final result = await api.confirmExecution(reviewId);
      expect(result.stage, 'observing');
      expect(result.disposition, 'accepted');
      expect(adapter.dispatchLaunches, 1);
      expect(await harness.modes(), ['inspect', 'inspect', 'dispatch']);
      final durable = await adapter.journal.read();
      expect(durable?.operationId, review.operationId);
      expect(durable?.stage.wire, 'observing');

      final restartedAdapter = harness.adapter();
      final restartedApi = harness.api(restartedAdapter);
      final restored = await restartedApi.currentExecution();
      expect(restored?.operationId, review.operationId);
      expect(restored?.stage, 'needs_attention');
      expect(restartedAdapter.dispatchLaunches, 0);
      await restartedApi.credentialsForRole('source', _sourceDataset);
      await restartedApi.credentialsForRole('target', _targetDataset);
      final rediscovered = await restartedApi.discover();
      expect(rediscovered.routers, hasLength(3));
      final checked = await restartedApi.checkExecution(review.operationId);
      expect(checked.stage, 'observing');
      expect(checked.reason, 'verification_pending');
      expect(restartedAdapter.dispatchLaunches, 0);
      expect(
          await harness.modes(), ['inspect', 'inspect', 'dispatch', 'observe']);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('uncertain result restores without sending another command', () async {
    expect(Platform.isMacOS, isTrue,
        reason: 'Mac execution test requires macOS');
    expect(File(_journalHelper).existsSync(), isTrue,
        reason: 'Build the explicit native move journal test helper first');
    final root = await Directory.systemTemp.createTemp('tnt-mac-uncertain-');
    final harness = _Harness(root);
    try {
      await harness.initialize();
      await harness.uncertainMarker.writeAsString('synthetic');
      final firstAdapter = harness.adapter();
      final api = harness.api(firstAdapter);
      final (reviewId, blockers) =
          await _review(api, eero: true, wholeGroup: true);
      expect(blockers, isEmpty);
      final review = await api.prepareExecution(reviewId);
      final uncertain = await api.confirmExecution(reviewId);
      expect(uncertain.stage, 'needs_attention');
      expect(uncertain.disposition, 'uncertain');
      expect(await harness.modes(), ['inspect', 'inspect', 'dispatch']);

      final secondAdapter = harness.adapter();
      final recoveryFixture = _ReadFixture()..changedSourceEndpoint = true;
      final secondApi = harness.api(secondAdapter, fixture: recoveryFixture);
      final restored = await secondApi.currentExecution();
      expect(restored?.operationId, review.operationId);
      expect(restored?.stage, 'needs_attention');
      expect(secondAdapter.dispatchLaunches, 0);
      await secondApi.credentialsForRole('source', _sourceDataset);
      await secondApi.credentialsForRole('target', _targetDataset);
      await secondApi.discover();
      final changed = await secondApi.checkExecution(review.operationId);
      expect(changed.stage, 'needs_attention');
      expect(secondAdapter.dispatchLaunches, 0);
      expect(await harness.modes(), ['inspect', 'inspect', 'dispatch']);
      recoveryFixture.changedSourceEndpoint = false;
      await secondApi.discover();
      final checked = await secondApi.checkExecution(review.operationId);
      expect(checked.stage, 'observing');
      expect(secondAdapter.dispatchLaunches, 0);
      expect(
          await harness.modes(), ['inspect', 'inspect', 'dispatch', 'observe']);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
