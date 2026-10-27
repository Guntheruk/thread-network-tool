// Test-only signed-parent route for the opt-in Mac move worker. Production
// main.dart never imports this file, and every endpoint is forced to ::1.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _profile = 'eero-source-network-alpha-v1';
const _prefix = 'TNT_MAC_SANDBOX ';

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

String _dataset(bool target) {
  final fields = <(int, List<int>)>[
    (0, [0, 0, 15]), (1, [0x12, 0x34]),
    (2, List.filled(8, target ? 2 : 1)), (3, ascii.encode('Lab')),
    (4, List.filled(16, target ? 0xbb : 0xaa)),
    (5, List.filled(16, target ? 0x22 : 0x11)),
    (7, [0xfd, 0, 0, 0, 0, 0, 0, 1]), (12, [0, 0, 0]),
    (14, [0, 0, 0, 0, 0, target ? 10 : 20, 0, 0]),
    (53, [0, 4, 0, 0x1f, 0xff, 0xe0]),
  ];
  return fields.expand((field) => [field.$1, field.$2.length, ...field.$2])
      .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<(int, String)> _child(String executable, List<String> arguments,
    {String? input, int seconds = 90}) async {
  final process = await Process.start(executable, arguments, runInShell: false);
  final output = <int>[];
  var invalid = false;
  final outDone = process.stdout.listen((bytes) {
    if (output.length + bytes.length > 16384) {
      invalid = true;
      process.kill(ProcessSignal.sigkill);
    } else {
      output.addAll(bytes);
    }
  }).asFuture<void>();
  final errDone = process.stderr.drain<void>();
  if (input != null) process.stdin.write(input);
  await process.stdin.close();
  final code = await process.exitCode.timeout(Duration(seconds: seconds),
      onTimeout: () {
    process.kill(ProcessSignal.sigkill);
    return process.exitCode;
  });
  await Future.wait([outDone, errDone]);
  if (invalid) throw const FormatException();
  return (code, utf8.decode(output));
}

Map<String, dynamic> _json((int, String) reply) {
  final parsed = jsonDecode(reply.$2);
  if (parsed is! Map<String, dynamic> || parsed['schema_version'] != 1) {
    throw const FormatException();
  }
  return parsed;
}

String _workerInput(String mode, String operation, String directory,
    List<int> sourcePorts, int targetPort, {int fencedAt = 0,
    String expected = '-'}) {
  final sourceRows = sourcePorts.map((port) =>
      'source_router ${_digest('::1:$port')} ::1 $port\n').join();
  return 'TNT-MAC-MOVE/1\nmode $mode\noperation_id $operation\n'
      'review_revision ${'b' * 64}\nsource_generation 1\n'
      'target_generation 2\nsession_id ${'c' * 64}\n'
      'discovery_revision ${'d' * 64}\n'
      'connectivity_revision ${'e' * 64}\n'
      'source_dataset ${_dataset(false)}\ntarget_dataset ${_dataset(true)}\n'
      'source_count ${sourcePorts.length}\n$sourceRows'
      'target_router ${_digest('::1:$targetPort')} ::1 $targetPort\n'
      'delay_ms 300000\ninventory_attestation ${'f' * 64}\n'
      'controlled_empty yes\nmanual_recovery yes\n'
      'lifecycle_directory $directory\nfenced_at_ms $fencedAt\n'
      'expected_binding $expected\nEND\n';
}

String _fence(String operation, Map<String, dynamic> inspected, int at,
    {bool corrupt = false, int revision = 1,
    String stage = 'dispatch_fenced', String disposition = 'unknown',
    String reason = 'none'}) {
  final bindings = List<String>.from(inspected['source_bindings'] as List)..sort();
  final source = corrupt ? '0' * 64 : inspected['source_commitment'] as String;
  return 'schema=1\noperation=$operation\nrevision=$revision\nprofile=$_profile\n'
      'stage=$stage\ndisposition=$disposition\nsource=$source\n'
      'target=${inspected['target_commitment']}\n'
      'target_router=${inspected['target_binding']}\n'
      'routers=${bindings.join(',')}\nfenced_at_ms=$at\n'
      'observe_until_ms=${at + 330000}\nobservation_seconds=30\n'
      'stable_since_ms=0\nstable_last_ms=0\nreason=$reason\n';
}

List<int> _ports(String? raw) {
  if (raw == null || raw.isEmpty) throw const FormatException();
  final parts = raw.split(',').map(int.tryParse).toList();
  if (parts.isEmpty || parts.length > 8 ||
      parts.any((port) => port == null || port < 1 || port > 65535) ||
      parts.toSet().length != parts.length) {
    throw const FormatException();
  }
  return parts.cast<int>();
}

Future<void> _emit(Map<String, Object?> event) async {
  stdout.writeln('$_prefix${jsonEncode(event)}');
  await stdout.flush();
}

Future<void> _run() async {
  final env = Platform.environment;
  final scenario = env['TNT_MOVE_SCENARIO'];
  final sourcePorts = _ports(env['TNT_MOVE_SOURCE_PORTS']);
  final targetPort = int.tryParse(env['TNT_MOVE_TARGET_PORT'] ?? '');
  final nonce = env['TNT_MOVE_NONCE'];
  if (!Platform.isMacOS ||
      !{'accept', 'reject', 'fence_mismatch', 'changed_target', 'silent_target'}
          .contains(scenario) ||
      targetPort == null || targetPort < 1 || targetPort > 65535 ||
      sourcePorts.contains(targetPort) ||
      nonce == null || !RegExp(r'^[0-9a-f]{16}$').hasMatch(nonce)) {
    throw const FormatException();
  }
  final helpers = '${File(Platform.resolvedExecutable).parent.parent.path}/Helpers';
  final worker = '$helpers/tnt-mac-move-worker';
  final journal = '$helpers/thread-move-journal';
  if (!File(worker).existsSync() || !File(journal).existsSync()) {
    throw const FileSystemException();
  }
  final capabilities = _json(await _child(worker, ['capabilities']));
  if (capabilities['profile_id'] != _profile ||
      capabilities['network_writes'] != true ||
      capabilities['durable_fence'] != true) {
    throw const FormatException();
  }
  const channel = MethodChannel('thread_network_tool/move_storage');
  final privateRoot = await channel.invokeMethod<String>('privateDirectory');
  if (privateRoot == null || !Directory(privateRoot).isAbsolute) {
    throw const FormatException();
  }
  final directory = '$privateRoot/sandbox-fixture-$nonce';
  final operation = _digest('TNT-MAC-SANDBOX/1\n$nonce\n');
  final initialized = await _child(journal, ['initialize', directory]);
  if (initialized != (0, 'ready\n')) {
    throw const FormatException();
  }
  final inspect = await _child(worker, [], input: _workerInput(
      'inspect', operation, directory, sourcePorts, targetPort));
  final inspected = _json(inspect);
  if (inspect.$1 != 0 || inspected['ready'] != true ||
      inspected['profile_id'] != _profile) {
    throw const FormatException();
  }
  await _emit({'stage': 'inspected', 'scenario': scenario,
    'capabilities': true, 'journal_initialized': true,
    'authenticated_snapshots': true});

  // The runner may replace a synthetic ::1 peer between inspect and dispatch.
  final commands = StreamIterator<String>(stdin.transform(utf8.decoder)
      .transform(const LineSplitter()));
  Future<void> continueWhenReady() async {
    if (!(await commands.moveNext().timeout(const Duration(seconds: 30))) ||
        commands.current != 'continue') {
      throw const FormatException();
    }
  }
  await continueWhenReady();
  final at = DateTime.now().toUtc().millisecondsSinceEpoch;
  final corrupt = scenario == 'fence_mismatch';
  final began = await _child(journal, ['begin', directory],
      input: _fence(operation, inspected, at, corrupt: corrupt));
  if (began.$1 != 0 || !began.$2.contains('stage=dispatch_fenced\n')) {
    throw const FormatException();
  }
  final read = await _child(journal, ['read', directory]);
  if (read.$1 != 0 || read.$2 != began.$2) {
    throw const FormatException();
  }
  final dispatch = await _child(worker, [], seconds: 150, input: _workerInput(
      'dispatch', operation, directory, sourcePorts, targetPort,
      fencedAt: at, expected: inspected['binding_commitment'] as String));
  final outcome = _json(dispatch);
  await _emit({'stage': 'dispatched', 'scenario': scenario,
    'fence_persisted': true, 'worker_exit': dispatch.$1,
    'disposition': outcome['disposition'] is String
        ? outcome['disposition'] : 'unknown',
    'reason': outcome['reason'] is String ? outcome['reason'] : 'unknown',
    'petitions': outcome['petitions'] is int ? outcome['petitions'] : null,
    'pending_set_invocations': outcome['pending_set_invocations'] is int
        ? outcome['pending_set_invocations'] : null});
  if (scenario == 'accept' || scenario == 'reject') {
    // The runner swaps only synthetic peers to model the state after delay.
    await continueWhenReady();
    final updated = await _child(journal, ['update', directory, '1'],
        input: _fence(operation, inspected, at, revision: 2,
            stage: 'observing',
            disposition: scenario == 'accept' ? 'accepted' : 'rejected',
            reason: scenario == 'accept' ? 'worker_accepted' : 'worker_rejected'));
    if (updated.$1 != 0 || !updated.$2.contains('stage=observing\n')) {
      throw const FormatException();
    }
    final observation = await _child(worker, [], seconds: 120,
        input: _workerInput('observe', operation, directory, sourcePorts,
            targetPort, fencedAt: at));
    final readback = _json(observation);
    if (observation.$1 != 0) throw const FormatException();
    await _emit({'stage': 'observed', 'scenario': scenario,
      'configuration_read': true,
      'converged': readback['converged'] == true,
      'original_source_unchanged_rejected':
          readback['original_source_unchanged_rejected'] == true,
      'target_unchanged': readback['target_unchanged'] == true,
      'source_count': readback['sources'] is List
          ? (readback['sources'] as List).length : 0});
  }
  // These directories contain only synthetic test records and are uniquely
  // named under the app's private support directory.
  await Directory(directory).delete(recursive: true);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(
      child: Text('Isolated Mac move sandbox fixture')))));
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await _run();
      exit(0);
    } catch (_) {
      await _emit({'stage': 'failed', 'reason': 'fixture_execution'});
      exit(1);
    }
  });
}
