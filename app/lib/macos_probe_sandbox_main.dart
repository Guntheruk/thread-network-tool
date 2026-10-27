// Test-only Flutter entrypoint. The production main.dart never imports this.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'native/session.dart';

String dataset(String scenario) {
  final name = scenario == 'identity_mismatch' ? 'OtherMesh' : 'Synthetic';
  final pskc = scenario == 'wrong_credential' ? 0xcc : 0xaa;
  final parts = <(int, List<int>)>[
    (0, [0, 0, 15]), (1, [0x12, 0x34]), (2, [1,2,3,4,5,6,7,8]),
    (3, utf8.encode(name)), (4, List.filled(16, pskc)),
    (5, List.filled(16, 0xbb)), (7, List.filled(8, 0xfd)),
    (12, [0,0,0]), (14, [0,0,0,0,0,0,0,1]), (53, [0,4,0,1,0,0]),
  ];
  return parts.expand((part) => [part.$1, part.$2.length, ...part.$2])
      .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> runProbe() async {
  final scenario = Platform.environment['TNT_PROBE_SCENARIO'];
  final port = int.tryParse(Platform.environment['TNT_PROBE_PORT'] ?? '');
  if (!{'success', 'identity_mismatch', 'wrong_credential', 'timeout'}
          .contains(scenario) || port == null || port < 1 || port > 65535 ||
      !Platform.isMacOS) {
    stdout.writeln('TNT_SANDBOX_PROBE {"status":"invalid_setup"}');
    exit(2);
  }
  final helper = '${File(Platform.resolvedExecutable).parent.parent.path}'
      '/Helpers/thread-network';
  if (!File(helper).existsSync()) {
    stdout.writeln('TNT_SANDBOX_PROBE {"status":"helper_missing"}');
    exit(2);
  }
  final process = NativeProcess(helper);
  Future<NativeReply> call(List<String> args, String? credential) =>
      args.first == 'discover'
          ? Future.value(NativeReply(0, {
              'schema_version': 1,
              'discovery_status': 'completed',
              'routers': [
                {'service_name': 'Synthetic fixture', 'address': '::1',
                 'port': port, 'network_name': 'Synthetic'}
              ],
            }))
          : process.call(args, credential);
  final session = LiveSession(call, permitLoopbackFixture: true);
  try {
    await session.perform('credentials', {'dataset': dataset(scenario!)});
    final discovered = await session.perform('discover', {});
    final routers = discovered['routers'] as List;
    final router = routers.single as Map;
    final state = await session.perform('probe', {'router_id': router['id']});
    final probe = (state['routers'] as List).single['probe'] as Map;
    stdout.writeln('TNT_SANDBOX_PROBE ${jsonEncode({
      'scenario': scenario,
      'status': probe['probe_status'],
      'authenticated': probe['authenticated'],
      'identity_match': probe['identity_match'],
      'active_status': probe['active_status'],
      'pending_status': probe['pending_status'],
    })}');
    exit(0);
  } catch (_) {
    stdout.writeln('TNT_SANDBOX_PROBE ${jsonEncode({
      'scenario': scenario, 'status': 'session_error'
    })}');
    exit(1);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(
      child: Text('Isolated authenticated read fixture')))));
  WidgetsBinding.instance.addPostFrameCallback((_) { runProbe(); });
}
