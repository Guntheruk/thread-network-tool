import 'dart:io';

import 'live_api.dart';
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

LiveApi platformLiveApi() {
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
  return NativeLiveApi(
      native: NativeProcess(engine, discoveryExecutable: discovery).call);
}
