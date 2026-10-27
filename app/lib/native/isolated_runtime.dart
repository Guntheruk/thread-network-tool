import 'dart:io';

import '../move/native_move_journal.dart';
import '../native_live_api.dart';
import 'native_move_adapter.dart';
import 'session.dart';

/// Explicit isolated application assembly, shared by the actual screen runner
/// and runtime test. Default platform routing never calls this entry point.
class IsolatedMoveRuntime {
  IsolatedMoveRuntime._(this.fixture, this.adapter, this.session, this.api);
  final IsolatedFixtureClient fixture;
  final NativeMoveAdapter adapter;
  final LiveSession session;
  final NativeLiveApi api;

  static IsolatedMoveRuntime fromEnvironment(Map<String, String> environment) {
    if (!Platform.isLinux) throw StateError('isolated Linux profile required');
    String path(String key, [String? fallback]) {
      final value = environment[key] ?? fallback;
      if (value == null ||
          !File(value).isAbsolute ||
          value.contains('\n') ||
          value.contains('\r') ||
          value.length > 1024) {
        throw StateError('invalid isolated runtime configuration');
      }
      return value;
    }

    final fixture = IsolatedFixtureClient(path('TNT_FIXTURE_SOCKET'));
    final native =
        NativeProcess(path('TNT_ENGINE_PATH', '/opt/app-build/thread-network'));
    Future<NativeReply> read(List<String> arguments, String? credential) async {
      if (arguments.first == 'discover') {
        return NativeReply(0, await fixture.call('discover'));
      }
      return native.call(arguments, credential);
    }

    final adapter = NativeMoveAdapter(
      workerExecutable: path('TNT_MOVE_WORKER'),
      manifestPath: path('TNT_FIXTURE_MANIFEST'),
      lifecycleDirectory: path('TNT_MOVE_LIFECYCLE_DIRECTORY'),
      fixture: fixture,
      journal: NativeMoveJournal(
        executable: path('TNT_MOVE_JOURNAL'),
        directory: path('TNT_MOVE_JOURNAL_DIRECTORY'),
      ),
    );
    final session = LiveSession(read, execution: adapter);
    return IsolatedMoveRuntime._(fixture, adapter, session,
        NativeLiveApi(native: read, session: session));
  }
}
