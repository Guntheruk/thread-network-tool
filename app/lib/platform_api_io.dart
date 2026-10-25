import 'dart:io';

import 'live_api.dart';
import 'native/session.dart';
import 'native_live_api.dart';

const _engineOverride = String.fromEnvironment('TNT_ENGINE_PATH');
const _discoveryOverride = String.fromEnvironment('TNT_DISCOVERY_ENGINE_PATH');

void configureRouting() {}

LiveApi platformLiveApi() {
  if (!Platform.isMacOS) return const UnsupportedLiveApi();

  final engine = _engineOverride.isEmpty
      ? File(
          '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/thread-network')
      : File(_engineOverride);
  if (!engine.isAbsolute || !engine.existsSync()) {
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
      native: NativeProcess(engine.path, discoveryExecutable: discovery).call);
}
