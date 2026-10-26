import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/move/native_move_journal.dart';
import 'package:thread_network_tool/native/mac_move_adapter.dart';

void main() {
  test('router binding survives restart only at the same numeric endpoint', () {
    final first = MacMoveRouter('192.168.10.4', 49154);
    final rediscovered = MacMoveRouter('192.168.10.4', 49154);
    final changedPort = MacMoveRouter('192.168.10.4', 49155);
    expect(rediscovered.identity, first.identity);
    expect(rediscovered.binding, first.binding);
    expect(changedPort.binding, isNot(first.binding));
    expect(() => MacMoveRouter('eero.local', 49154), throwsFormatException);
  });

  test('Mac request uses strict stdin protocol with one whole-source group',
      () {
    final sourceA = MacMoveRouter('192.168.10.4', 49154);
    final sourceB = MacMoveRouter('192.168.10.5', 49154);
    final target = MacMoveRouter('192.168.10.6', 49154);
    final request = MacMoveRequest(
      operationId: 'a' * 64,
      reviewId: 'b' * 64,
      sourceDataset: 'abcd',
      targetDataset: 'ef01',
      sourceGeneration: 1,
      targetGeneration: 2,
      sessionId: 'c' * 64,
      discoveryRevision: 'd' * 64,
      connectivityRevision: 'e' * 64,
      sources: [sourceB, sourceA],
      target: target,
      inventoryAttestation: 'b' * 64,
    );
    final lines = request.encode('inspect', '/private/move').split('\n');
    expect(lines.first, 'TNT-MAC-MOVE/1');
    expect(lines, contains('source_count 2'));
    expect(lines, contains('source_router ${sourceA.wire}'));
    expect(lines, contains('source_router ${sourceB.wire}'));
    final sourceLines =
        lines.where((line) => line.startsWith('source_router ')).toList();
    expect(
        sourceLines,
        request.orderedSources
            .map((router) => 'source_router ${router.wire}')
            .toList());
    expect(lines, contains('target_router ${target.wire}'));
    expect(lines, contains('controlled_empty yes'));
    expect(lines, contains('manual_recovery yes'));
    expect(lines, contains('expected_binding -'));
  });

  test('a failed isolated worker cannot prepare or dispatch', () async {
    if (!Platform.isMacOS) return;
    final temporary = await Directory.systemTemp.createTemp('tnt-mac-adapter-');
    try {
      final journalScript = File('${temporary.path}/journal');
      await journalScript.writeAsString('''#!/bin/sh
case "\$1" in
  initialize) printf 'ready\\n' ;;
  read) printf 'empty\\n' ;;
  *) exit 1 ;;
esac
''');
      await Process.run('chmod', ['700', journalScript.path]);
      final worker = File('${temporary.path}/worker');
      await worker.writeAsString('''#!/bin/sh
printf '%s' "\$#" > '${temporary.path}/arg-count'
cat >/dev/null
printf 'invalid-json'
''');
      await Process.run('chmod', ['700', worker.path]);
      final adapter = MacMoveAdapter(
        workerExecutable: worker.path,
        lifecycleDirectory: '${temporary.path}/move-journal',
        journal: NativeMoveJournal(
          executable: journalScript.path,
          directory: '${temporary.path}/move-journal',
        ),
      );
      final request = MacMoveRequest(
        operationId: 'a' * 64,
        reviewId: 'b' * 64,
        sourceDataset: 'abcd',
        targetDataset: 'ef01',
        sourceGeneration: 1,
        targetGeneration: 2,
        sessionId: 'c' * 64,
        discoveryRevision: 'd' * 64,
        connectivityRevision: 'e' * 64,
        sources: [MacMoveRouter('192.168.10.4', 49154)],
        target: MacMoveRouter('192.168.10.6', 49154),
        inventoryAttestation: 'b' * 64,
      );
      await expectLater(adapter.prepare(request), throwsA(isA<Exception>()));
      expect(adapter.dispatchLaunches, 0);
      expect(await File('${temporary.path}/arg-count').readAsString(), '0');
    } finally {
      await temporary.delete(recursive: true);
    }
  });
}
