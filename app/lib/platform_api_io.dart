import 'dart:io';

import 'package:flutter/services.dart';

import 'live_api.dart';
import 'move/native_move_journal.dart';
import 'native/mac_move_adapter.dart';
import 'native/session.dart';
import 'native_live_api.dart';

const _engineOverride = String.fromEnvironment('TNT_ENGINE_PATH');
const _discoveryOverride = String.fromEnvironment('TNT_DISCOVERY_ENGINE_PATH');

void configureRouting() {}

/// Resolves the bundled helper, or an explicitly supplied absolute development
/// override. A missing or relative override never falls back to the bundle.
String? resolveNativeEnginePath({
  required String resolvedExecutable,
  String engineOverride = '',
  bool Function(String path)? exists,
}) {
  final path = engineOverride.isEmpty
      ? '${File(resolvedExecutable).parent.parent.path}/Helpers/thread-network'
      : engineOverride;
  final file = File(path);
  if (!file.isAbsolute || !(exists?.call(path) ?? file.existsSync())) {
    return null;
  }
  return file.path;
}

Future<LiveApi> platformLiveApi() async {
  if (!Platform.isMacOS) return const UnsupportedLiveApi();

  final engine = resolveNativeEnginePath(
    resolvedExecutable: Platform.resolvedExecutable,
    engineOverride: _engineOverride,
  );
  if (engine == null) {
    return const UnsupportedLiveApi();
  }

  String? discovery;
  if (_discoveryOverride.isNotEmpty) {
    final path = File(_discoveryOverride);
    if (!path.isAbsolute || !path.existsSync()) {
      return const UnsupportedLiveApi();
    }
    discovery = path.path;
  }
  final native = NativeProcess(engine, discoveryExecutable: discovery).call;
  final helpers = File(Platform.resolvedExecutable).parent.parent.path;
  final worker = File('$helpers/Helpers/tnt-mac-move-worker');
  final journalHelper = File('$helpers/Helpers/thread-move-journal');
  if (!journalHelper.existsSync()) return NativeLiveApi(native: native);
  try {
    const channel = MethodChannel('thread_network_tool/move_storage');
    final parent = await channel.invokeMethod<String>('privateDirectory');
    if (parent == null || !Directory(parent).isAbsolute) {
      return NativeLiveApi(native: native);
    }
    final directory = '$parent/move-journal';
    final adapter = MacMoveAdapter(
      workerExecutable: worker.path,
      lifecycleDirectory: directory,
      journal: NativeMoveJournal(
        executable: journalHelper.path,
        directory: directory,
      ),
    );
    return NativeLiveApi(
        native: native, session: LiveSession(native, execution: adapter));
  } catch (_) {
    return NativeLiveApi(native: native);
  }
}
