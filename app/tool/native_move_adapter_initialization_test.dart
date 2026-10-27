// Standalone Dart with a real native journal helper; no fixture or worker calls.
// Run: dart app/tool/native_move_adapter_initialization_test.dart /path/to/helper
import 'dart:convert';
import 'dart:io';

import 'package:thread_network_tool/move/move_execution.dart';
import 'package:thread_network_tool/move/native_move_journal.dart';
import 'package:thread_network_tool/native/native_move_adapter.dart';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> expectBusy(Future<void> attempt) async {
  try {
    await attempt;
  } on MoveExecutionFailure catch (error) {
    expect(error.code == 'journal_busy', 'Expected journal_busy');
    return;
  }
  throw StateError('Expected lock contention');
}

Future<Process> lockJournal(String directory) async {
  final holder = await Process.start('python3', [
    '-u',
    '-c',
    'import fcntl,sys; f=open(sys.argv[1], "rb"); '
        'fcntl.flock(f, fcntl.LOCK_EX); print("locked", flush=True); sys.stdin.read()',
    '$directory/writer.lock',
  ]);
  final ready = await holder.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 5));
  expect(ready == 'locked', 'Independent process must hold the journal lock');
  return holder;
}

Future<void> releaseJournal(Process holder) async {
  await holder.stdin.close();
  expect(
    await holder.exitCode.timeout(const Duration(seconds: 5)) == 0,
    'Lock holder must exit cleanly',
  );
}

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Supply native journal executable');
  final root = await Directory.systemTemp.createTemp('tnt-adapter-init-');
  Process? holder;
  try {
    final journal = NativeMoveJournal(
      executable: args.single,
      directory: '${root.path}/journal',
    );
    await journal.initialize();
    final adapter = NativeMoveAdapter(
      workerExecutable: '${root.path}/unused-worker',
      manifestPath: '${root.path}/unused-manifest',
      lifecycleDirectory: '${root.path}/unused-lifecycle',
      fixture: IsolatedFixtureClient('${root.path}/unused-socket'),
      journal: journal,
    );
    holder = await lockJournal(journal.directory);
    final failed = adapter.initialize();
    final concurrent = adapter.initialize();
    expect(
      identical(failed, concurrent),
      'Concurrent callers share initialization',
    );
    await Future.wait([expectBusy(failed), expectBusy(concurrent)]);
    await releaseJournal(holder);
    holder = null;
    await journal.initialize();
    final retry = adapter.initialize();
    expect(!identical(retry, failed), 'Failed initialization must be evicted');
    expect(
      identical(retry, adapter.initialize()),
      'Concurrent retry is shared',
    );
    await retry;

    holder = await lockJournal(journal.directory);
    await expectBusy(journal.initialize());
    final cached = adapter.initialize();
    expect(identical(cached, retry), 'Successful initialization stays cached');
    await cached;
    expect(
      adapter.dispatchLaunches == 0,
      'Initialization cannot dispatch worker',
    );
    await releaseJournal(holder);
    holder = null;
    expect(await journal.read() == null, 'No operation or fence was created');
    stdout.writeln(
      'PASS adapter retries real journal contention, shares attempts, and caches success',
    );
  } finally {
    if (holder != null) await releaseJournal(holder);
    await root.delete(recursive: true);
  }
}
