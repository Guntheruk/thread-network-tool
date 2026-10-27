import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/isolated_main.dart';
import 'package:thread_network_tool/move/move_execution.dart';
import 'package:thread_network_tool/move/native_move_journal.dart';
import 'package:thread_network_tool/native/native_move_adapter.dart';
import 'package:thread_network_tool/native/session.dart';
import 'package:thread_network_tool/native_live_api.dart';

void main() {
  final helper = Platform.environment['TNT_MOVE_JOURNAL'] ??
      Platform.environment['TNT_JOURNAL_CLI'];
  testWidgets('main startup displays a real saved fence with failed fixture',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('tnt-startup-recovery-');
    addTearDown(() => root.deleteSync(recursive: true));
    final journal = NativeMoveJournal(
        executable: helper!, directory: '${root.path}/journal');
    final now = DateTime.now().toUtc();
    final record = MoveRecord(
      operationId: 'e' * 64,
      revision: 1,
      profileId: isolatedMoveProfile,
      stage: MoveStage.dispatchFenced,
      disposition: MoveDisposition.unknown,
      sourceCommitment: 'a' * 64,
      targetCommitment: 'b' * 64,
      targetRouterBinding: 'd' * 64,
      routerBindings: ['c' * 64],
      fencedAt: now.subtract(const Duration(seconds: 1)),
      observeUntil: now.add(const Duration(seconds: 330)),
      observationSeconds: 30,
      reason: 'none',
    );
    await tester.runAsync(() async {
      await journal.initialize();
      await journal.begin(record);
    });
    final fixture = IsolatedFixtureClient('${root.path}/missing-fixture');
    // Establish that this is a real failing fixture dependency, not a mock API.
    await tester.runAsync(() async {
      await expectLater(
          fixture.call('discover'), throwsA(isA<SocketException>()));
    });
    final native = NativeProcess(helper).call;
    Future<NativeReply> read(List<String> args, String? credential) async =>
        args.first == 'discover'
            ? NativeReply(0, await fixture.call('discover'))
            : native(args, credential);
    final adapter = NativeMoveAdapter(
      workerExecutable: helper,
      manifestPath: '${root.path}/missing-manifest',
      lifecycleDirectory: root.path,
      fixture: fixture,
      journal: journal,
    );
    final session = LiveSession(read, execution: adapter);
    final api = NativeLiveApi(native: read, session: session);
    // Invoke the exact bootstrap helper used by isolated_main.main().
    final app = await tester.runAsync(() => bootstrapIsolatedApplication(api));
    await tester.runAsync(() async {
      await tester.pumpWidget(app!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (
        find.byKey(const Key('move-execution-operation')).evaluate().isEmpty &&
            DateTime.now().isBefore(end)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Operation: ${record.operationId}'), findsOneWidget);
    expect(find.text('Stage: needs attention'), findsOneWidget);
    expect(find.text('Disposition: uncertain'), findsOneWidget);
    expect(session.state['discovery_status'], 'idle');
    expect(adapter.dispatchLaunches, 0);
    final saved = await tester.runAsync(journal.read);
    expect(saved?.operationId, record.operationId);
    expect(saved?.stage, MoveStage.needsAttention);
    expect(saved?.terminal, isFalse);
    expect(find.byKey(const Key('move-execution-confirm')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: helper == null || (!Platform.isMacOS && !Platform.isLinux));
}
