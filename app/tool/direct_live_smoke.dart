import 'dart:convert';
import 'dart:io';

import 'package:thread_network_tool/native/session.dart';
import 'package:thread_network_tool/native_live_api.dart';

/// Optional authorized live check of the native Flutter adapter, without HTTP.
/// Args are executable path, exact discovered service name, optional discovery
/// executable. Credential input is one line on stdin; output omits identities.
Future<void> main(List<String> args) async {
  try {
    if (args.length < 2 || args.length > 3 || !File(args[0]).isAbsolute) {
      throw const FormatException();
    }
    final bytes = <int>[];
    await for (final chunk in stdin.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 510) throw const FormatException();
      bytes.addAll(chunk);
    }
    final api = NativeLiveApi(
        native: NativeProcess(args[0],
                discoveryExecutable: args.length == 3 ? args[2] : null)
            .call);
    await api.credentials(utf8.decode(bytes).trim());
    bytes.fillRange(0, bytes.length, 0);
    final discovered = await api.discover();
    final selected =
        discovered.routers.where((r) => r.serviceName == args[1]).toList();
    if (selected.length != 1) throw const FormatException();
    final result = await api.probe(selected.single.id);
    final proof =
        result.routers.singleWhere((r) => r.id == selected.single.id).probe!;
    stdout.writeln(jsonEncode({
      'mode': 'native_direct',
      'discovery_status': result.discoveryStatus,
      'advertised_router_count': result.routers.length,
      'probe_status': proof.probeStatus,
      'authenticated': proof.authenticated,
      'identity_match': proof.identityMatch,
      'active_status': proof.activeStatus,
      'pending_status': proof.pendingStatus,
      'verified': proof.verified,
    }));
    if (!proof.verified) exitCode = 1;
  } catch (_) {
    stderr.writeln('Direct native check failed; sensitive details suppressed.');
    exitCode = 1;
  }
}
