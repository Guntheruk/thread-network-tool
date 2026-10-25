// Standalone Dart: real native journal processes, injected network worker.
// Run: dart app/tool/move_execution_test.dart /path/to/thread-network-journal
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:thread_network_tool/move/move_execution.dart';
import 'package:thread_network_tool/move/move_execution_controller.dart';
import 'package:thread_network_tool/move/move_journal.dart';
import 'package:thread_network_tool/move/native_move_journal.dart';

String hex(String c) => c * 64;
void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> failure(Future<Object?> action, String code) async {
  try {
    await action;
  } on MoveExecutionFailure catch (error) {
    expect(error.code == code, 'Expected $code, got ${error.code}');
    return;
  }
  throw StateError('Expected failure $code');
}

class Rig {
  Rig(this.journal);
  final MoveJournal journal;
  DateTime clock = DateTime.utc(2026, 10, 25, 12);
  int calls = 0;
  int observationCalls = 0;
  bool mismatch = false;
  bool profileVerified = true;
  bool runtimeVerified = true;
  bool independentDeadline = true;
  bool throwingWorker = false;
  bool wrongWorkerId = false;
  bool workerTerminated = true;
  bool targetChanged = false;
  bool wrongTarget = false;
  bool missingRouter = false;
  bool bindingVerified = true;
  bool sourceUnchanged = false;
  bool sourcePending = false;
  bool staleReads = false;
  bool targetPending = false;
  bool throwingObservation = false;
  Duration observationClockAdvance = Duration.zero;
  MoveDisposition disposition = MoveDisposition.accepted;
  Completer<void>? workerHold;
  Completer<void>? observeHold;
  late final controller = MoveExecutionController(
    journal: journal,
    now: () => clock,
    preflight: (plan) async => MovePreflight(
      bindingCommitment: mismatch ? hex('9') : plan.bindingCommitment,
      checkedAt: clock,
      profileVerified: profileVerified,
      runtimeVerified: runtimeVerified,
      workerHasIndependentDeadline: independentDeadline,
    ),
    worker: (plan) async {
      calls++;
      await workerHold?.future;
      if (throwingWorker) throw StateError('synthetic worker exception');
      return MoveWorkerResult(
        wrongWorkerId ? hex('9') : plan.operationId,
        disposition,
      );
    },
    observe: (record) async {
      observationCalls++;
      await observeHold?.future;
      if (throwingObservation) throw StateError('synthetic read failure');
      MoveRouterObservation read(String binding, {bool changed = false}) =>
          MoveRouterObservation(
            binding: binding,
            datasetCommitment: changed
                ? hex('9')
                : sourceUnchanged && record.routerBindings.contains(binding)
                    ? record.sourceCommitment
                    : record.targetCommitment,
            checkedAt: staleReads
                ? clock.subtract(const Duration(seconds: 31))
                : clock,
            authenticated: true,
            pendingEmpty: record.routerBindings.contains(binding)
                ? !sourcePending
                : !targetPending,
            connectivityVerified: true,
          );
      final evidence = MoveObservation(
        operationId: record.operationId,
        recoveryBindingVerified: bindingVerified,
        workerTerminated: workerTerminated,
        sources: record.routerBindings
            .take(missingRouter ? 1 : 2)
            .map(read)
            .toList(),
        target: read(
          wrongTarget ? hex('9') : record.targetRouterBinding,
          changed: targetChanged,
        ),
      );
      clock = clock.add(observationClockAdvance);
      return evidence;
    },
  );
  MoveExecutionPlan plan({
    String id = 'a',
    String profile = isolatedMoveProfile,
  }) =>
      MoveExecutionPlan(
        reviewId: hex('0'),
        operationId: hex(id),
        profileId: profile,
        bindingCommitment: hex('1'),
        sourceCommitment: hex('b'),
        targetCommitment: hex('c'),
        targetRouterBinding: hex('f'),
        routerBindings: [hex('d'), hex('e')],
        expiresAt: clock.add(const Duration(minutes: 5)),
        delaySeconds: 300,
        observationSeconds: 10,
      );
}

class FailBegin implements MoveJournal {
  FailBegin(this.actual);
  final MoveJournal actual;
  @override
  Future<MoveRecord?> read() => actual.read();
  @override
  Future<MoveRecord> begin(MoveRecord record) async =>
      throw const MoveExecutionFailure('journal_unavailable');
  @override
  Future<MoveRecord> update(MoveRecord record, int revision) =>
      actual.update(record, revision);
}

// Hold the actual native helper's flock from an independent process.
Future<Process> lockJournal(String directory) async {
  final process = await Process.start('python3', [
    '-u',
    '-c',
    'import fcntl,sys; f=open(sys.argv[1], "rb"); '
        'fcntl.flock(f, fcntl.LOCK_EX); print("locked", flush=True); sys.stdin.read()',
    '$directory/writer.lock',
  ]);
  expect(
    await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first ==
        'locked',
    'Lock process must confirm ownership',
  );
  return process;
}

Future<void> releaseJournal(Process process) async {
  await process.stdin.close();
  expect(await process.exitCode == 0, 'Lock holder must exit cleanly');
}

class ReadHookJournal implements MoveJournal {
  ReadHookJournal(this.actual);
  final MoveJournal actual;
  Future<void> Function()? afterRead;
  @override
  Future<MoveRecord?> read() async {
    final result = await actual.read();
    final hook = afterRead;
    afterRead = null;
    await hook?.call();
    return result;
  }

  @override
  Future<MoveRecord> begin(MoveRecord record) => actual.begin(record);
  @override
  Future<MoveRecord> update(MoveRecord record, int expectedRevision) =>
      actual.update(record, expectedRevision);
}

Future<void> child(String helper, String directory, String boundary) async {
  final journal = NativeMoveJournal(executable: helper, directory: directory);
  final rig = Rig(journal);
  final controller = MoveExecutionController(
    journal: journal,
    preflight: rig.controller.preflight,
    now: () => rig.clock,
    observe: rig.controller.observe,
    worker: (plan) async {
      if (boundary == 'before_worker') exit(73);
      await File('$directory/synthetic_calls').writeAsString('1', flush: true);
      exit(73); // Worker was invoked; result was never persisted.
    },
  );
  await controller.confirmAndStart(rig.plan());
  throw StateError('Child did not exit at fault boundary');
}

// Each phase runs in a separate Dart process against the same native journal.
Future<void> restartObservationChild(
  String helper,
  String directory,
  String disposition,
  String phase,
  String entry,
) async {
  final rig = Rig(NativeMoveJournal(executable: helper, directory: directory));
  rig.disposition = MoveDisposition.values.byName(disposition);
  rig.sourceUnchanged = rig.disposition == MoveDisposition.rejected;
  if (phase == 'seed') {
    await rig.controller.confirmAndStart(rig.plan());
    rig.clock = rig.clock.add(const Duration(seconds: 310));
    expect(
      !(await rig.controller.checkOutcome(hex('a'))).terminal,
      'Seed sample must remain fenced',
    );
    return;
  }
  rig.clock = rig.clock.add(const Duration(seconds: 320));
  if (entry == 'current') {
    final recovered = await rig.controller.current();
    expect(
      recovered!.stableSince == null && recovered.stableLast == null,
      'current must initialize recovery without caller restore',
    );
  }
  final first = await rig.controller.checkOutcome(hex('a'));
  expect(
    !first.terminal && rig.observationCalls == 1,
    'Restart cannot reuse the previous process observation interval',
  );
  await failure(
    rig.controller.confirmAndStart(rig.plan(id: '2')),
    'unresolved_operation',
  );
  final revision = first.revision;
  expect(
    (await rig.controller.current())!.revision == revision,
    'Polling current must not reset active observation continuity',
  );
  expect(
    (await rig.controller.current())!.stableSince == rig.clock,
    'Polling current preserves the new interval',
  );
  rig.clock = rig.clock.add(const Duration(seconds: 10));
  final complete = await rig.controller.checkOutcome(hex('a'));
  expect(
    complete.stage ==
        (rig.sourceUnchanged
            ? MoveStage.verifiedUnchanged
            : MoveStage.verifiedComplete),
    'Fresh full post-restart interval must complete',
  );
  expect(
    rig.calls == 0 && rig.observationCalls == 2,
    'Recovery only performs fresh read observations',
  );
}

Future<void> main(List<String> args) async {
  if (args.length == 6 && args[0] == '--restart-observation') {
    await restartObservationChild(args[1], args[2], args[3], args[4], args[5]);
    return;
  }
  if (args.length == 4 && args[0] == '--child') {
    await child(args[1], args[2], args[3]);
    return;
  }
  if (args.length != 1) throw ArgumentError('Supply native journal executable');
  final helper = args.single;
  final parent = await Directory.systemTemp.createTemp('tnt-move-controller-');
  var count = 0;
  Future<void> test(String name, Future<void> Function(Rig) body) async {
    final journal = NativeMoveJournal(
      executable: helper,
      directory: '${parent.path}/case-${count++}',
    );
    await journal.initialize();
    await body(Rig(journal));
    stdout.writeln('PASS $name');
  }

  try {
    await test('initialization retries after real journal lock is released', (
      r,
    ) async {
      final journal = r.journal as NativeMoveJournal;
      final seeder = Rig(journal);
      await seeder.controller.confirmAndStart(seeder.plan());
      final lock = await lockJournal(journal.directory);
      try {
        await Future.wait([
          failure(r.controller.current(), 'journal_busy'),
          failure(r.controller.current(), 'journal_busy'),
        ]);
      } finally {
        await releaseJournal(lock);
      }
      final recovered = await r.controller.current();
      expect(
        recovered!.reason == 'restart_requires_reads',
        'Recovery retries after release',
      );
      final revision = recovered.revision;
      expect(
        (await r.controller.current())!.revision == revision,
        'Successful initialization stays cached',
      );
      expect(r.calls == 0, 'Recovery must not invoke worker');
    });
    await test(
      'unfamiliar recovery retries after real journal update contention',
      (r) async {
        final journal = r.journal as NativeMoveJournal;
        final hookJournal = ReadHookJournal(journal);
        final reader = Rig(hookJournal);
        expect(
          await reader.controller.current() == null,
          'Initialize before external operation',
        );
        await r.controller.confirmAndStart(r.plan());
        Process? lock;
        hookJournal.afterRead = () async {
          lock = await lockJournal(journal.directory);
        };
        try {
          await failure(reader.controller.current(), 'journal_busy');
        } finally {
          if (lock != null) await releaseJournal(lock!);
        }
        final recovered = await reader.controller.current();
        expect(
          recovered!.reason == 'restart_requires_reads',
          'Failed unfamiliar recovery must retry',
        );
        reader.clock = reader.clock.add(const Duration(seconds: 310));
        final first = await reader.controller.checkOutcome(
          recovered.operationId,
        );
        expect(!first.terminal, 'Fresh interval required');
        final revision = first.revision;
        expect(
          (await reader.controller.current())!.revision == revision,
          'Polling retains successful recovery',
        );
        reader.clock = reader.clock.add(const Duration(seconds: 10));
        expect(
          (await reader.controller.checkOutcome(
            recovered.operationId,
          ))
              .terminal,
          'Fresh interval survives retry',
        );
        expect(reader.calls == 0, 'Recovery cannot invoke worker');
      },
    );
    for (final rejected in [false, true]) {
      await test('read spanning deadline stays pending rejected=$rejected', (
        r,
      ) async {
        r.disposition =
            rejected ? MoveDisposition.rejected : MoveDisposition.accepted;
        r.sourceUnchanged = rejected;
        final operation = await r.controller.confirmAndStart(r.plan());
        r.clock = r.clock.add(const Duration(seconds: 298));
        await r.controller.checkOutcome(operation.operationId);
        r.clock = r.clock.add(const Duration(seconds: 11));
        r.observationClockAdvance = const Duration(seconds: 2);
        final pending = await r.controller.checkOutcome(operation.operationId);
        expect(
          !pending.terminal &&
              pending.stableLast!.isBefore(operation.observeUntil),
          'A sample before deadline must remain pending even when callback finishes after',
        );
        r.observationClockAdvance = Duration.zero;
        final complete = await r.controller.checkOutcome(operation.operationId);
        expect(
          complete.stage ==
              (rejected
                  ? MoveStage.verifiedUnchanged
                  : MoveStage.verifiedComplete),
          'Next fresh sample after deadline completes normally',
        );
        expect(r.calls == 1, 'Observation must not replay worker');
      });
    }
    await test('duplicate clicks reserve before await and launch once', (
      r,
    ) async {
      r.workerHold = Completer<void>();
      final plan = r.plan();
      final first = r.controller.confirmAndStart(plan);
      final second = r.controller.confirmAndStart(plan);
      expect(identical(first, second), 'Duplicate must share operation future');
      r.workerHold!.complete();
      expect(
        (await first).stage == MoveStage.observing,
        'Acceptance is observing',
      );
      await second;
      expect(r.calls == 1, 'Exactly one worker invocation');
    });
    await test('fresh operation id cannot bypass unresolved fence', (r) async {
      await r.controller.confirmAndStart(r.plan());
      await failure(
        r.controller.confirmAndStart(r.plan(id: '2')),
        'unresolved_operation',
      );
      expect(r.calls == 1, 'No second worker');
    });
    await test('changed private binding blocks dispatch', (r) async {
      r.mismatch = true;
      await failure(
        r.controller.confirmAndStart(r.plan()),
        'review_invalidated',
      );
      expect(
        r.calls == 0 && await r.journal.read() == null,
        'No fence or dispatch',
      );
    });
    for (final gate in ['profile', 'runtime', 'deadline']) {
      await test('missing $gate gate blocks dispatch', (r) async {
        r.profileVerified = gate != 'profile';
        r.runtimeVerified = gate != 'runtime';
        r.independentDeadline = gate != 'deadline';
        await failure(
          r.controller.confirmAndStart(r.plan()),
          'execution_unavailable',
        );
        expect(r.calls == 0, 'Unavailable route must not run worker');
      });
    }
    await test('unknown vendor profile is unavailable', (r) async {
      await failure(
        r.controller.confirmAndStart(r.plan(profile: 'unknown-vendor')),
        'unsupported_profile',
      );
      expect(r.calls == 0, 'No vendor guess');
    });
    await test('expired review requires new review', (r) async {
      final plan = r.plan();
      r.clock = r.clock.add(const Duration(minutes: 6));
      await failure(r.controller.confirmAndStart(plan), 'review_expired');
      expect(r.calls == 0, 'No expired write');
    });
    await test('durable fence failure prevents worker launch', (r) async {
      final broken = Rig(FailBegin(r.journal));
      await failure(
        broken.controller.confirmAndStart(broken.plan()),
        'journal_unavailable',
      );
      expect(broken.calls == 0, 'No launch without durable acknowledgement');
    });
    for (final kind in ['throw', 'wrong_id', 'unknown']) {
      await test('$kind worker result is uncertain and cannot replay', (
        r,
      ) async {
        r.throwingWorker = kind == 'throw';
        r.wrongWorkerId = kind == 'wrong_id';
        if (kind == 'unknown') r.disposition = MoveDisposition.unknown;
        final result = await r.controller.confirmAndStart(r.plan());
        expect(
          result.disposition == MoveDisposition.uncertain,
          'Must be uncertain',
        );
        await failure(
          r.controller.confirmAndStart(r.plan(id: '2')),
          'unresolved_operation',
        );
        expect(r.calls == 1, 'No uncertain retry');
      });
    }
    await test(
      'rejected remains fenced; proven-not-sent permits a new review',
      (r) async {
        r.disposition = MoveDisposition.provenNotSent;
        expect(
          (await r.controller.confirmAndStart(r.plan())).terminal,
          'Proven not sent is terminal',
        );
        r.disposition = MoveDisposition.rejected;
        final result = await r.controller.confirmAndStart(r.plan(id: '2'));
        expect(!result.terminal, 'Conservative rejected fence retained');
        await failure(
          r.controller.confirmAndStart(r.plan(id: '3')),
          'unresolved_operation',
        );
      },
    );
    await test(
      'completion requires two fresh matching observations spanning window',
      (r) async {
        final result = await r.controller.confirmAndStart(r.plan());
        r.clock = r.clock.add(const Duration(seconds: 310));
        final first = await r.controller.checkOutcome(result.operationId);
        expect(
          !first.terminal,
          'Late single read is not an observation period',
        );
        r.clock = r.clock.add(const Duration(seconds: 10));
        expect(
          (await r.controller.checkOutcome(result.operationId)).stage ==
              MoveStage.verifiedComplete,
          'Both source routers and target verified across interval',
        );
        expect(r.calls == 1, 'Observation cannot run worker');
      },
    );
    await test(
      'rejected operation verifies unchanged then requires a new explicit operation',
      (r) async {
        r.disposition = MoveDisposition.rejected;
        r.sourceUnchanged = true;
        final rejected = await r.controller.confirmAndStart(r.plan());
        r.clock = r.clock.add(const Duration(seconds: 310));
        expect(
          !(await r.controller.checkOutcome(rejected.operationId)).terminal,
          'One read cannot clear rejection',
        );
        r.clock = r.clock.add(const Duration(seconds: 10));
        final result = await r.controller.checkOutcome(rejected.operationId);
        expect(
          result.stage == MoveStage.verifiedUnchanged,
          'Both original datasets verified unchanged',
        );
        expect(r.calls == 1, 'Recovery did not send');
        expect(
          (await r.controller.confirmAndStart(r.plan())).stage ==
              MoveStage.verifiedUnchanged,
          'Old confirmation only returns result',
        );
        r.disposition = MoveDisposition.accepted;
        await r.controller.confirmAndStart(r.plan(id: '2'));
        expect(r.calls == 2, 'Only new explicit plan sends');
      },
    );
    for (final defect in [
      'missing_source',
      'source_pending',
      'target_changed',
      'target_pending',
      'worker_alive',
      'stale_read',
    ]) {
      await test('rejected recovery $defect retains fence', (r) async {
        r.disposition = MoveDisposition.rejected;
        r.sourceUnchanged = true;
        r.missingRouter = defect == 'missing_source';
        r.sourcePending = defect == 'source_pending';
        r.targetChanged = defect == 'target_changed';
        r.targetPending = defect == 'target_pending';
        r.workerTerminated = defect != 'worker_alive';
        r.staleReads = defect == 'stale_read';
        final result = await r.controller.confirmAndStart(r.plan());
        r.clock = r.clock.add(const Duration(seconds: 310));
        await r.controller.checkOutcome(result.operationId);
        r.clock = r.clock.add(const Duration(seconds: 10));
        expect(
          !(await r.controller.checkOutcome(result.operationId)).terminal,
          'Rejected recovery requires full fresh evidence',
        );
        await failure(
          r.controller.confirmAndStart(r.plan(id: '2')),
          'unresolved_operation',
        );
      });
    }
    await test('uncertain unchanged network can never clear the fence', (
      r,
    ) async {
      r.disposition = MoveDisposition.uncertain;
      r.sourceUnchanged = true;
      final result = await r.controller.confirmAndStart(r.plan());
      r.clock = r.clock.add(const Duration(seconds: 310));
      await r.controller.checkOutcome(result.operationId);
      r.clock = r.clock.add(const Duration(seconds: 10));
      expect(
        !(await r.controller.checkOutcome(result.operationId)).terminal,
        'Delayed pending update may still apply',
      );
    });
    await test(
      'a failed read breaks observation continuity and sanitizes errors',
      (r) async {
        final result = await r.controller.confirmAndStart(r.plan());
        r.clock = r.clock.add(const Duration(seconds: 310));
        await r.controller.checkOutcome(result.operationId);
        r.throwingObservation = true;
        final failed = await r.controller.checkOutcome(result.operationId);
        expect(
          failed.reason == 'verification_failed' && failed.stableSince == null,
          'Read failure must clear continuity',
        );
        r.throwingObservation = false;
        r.clock = r.clock.add(const Duration(seconds: 10));
        expect(
          !(await r.controller.checkOutcome(result.operationId)).terminal,
          'Fresh period starts again',
        );
      },
    );
    await test('observation gap and restart require a new stable interval', (
      r,
    ) async {
      final result = await r.controller.confirmAndStart(r.plan());
      r.clock = r.clock.add(const Duration(seconds: 310));
      await r.controller.checkOutcome(result.operationId);
      r.clock = r.clock.add(const Duration(seconds: 31));
      expect(
        !(await r.controller.checkOutcome(result.operationId)).terminal,
        'Gap breaks interval',
      );
      await r.controller.restore();
      r.clock = r.clock.add(const Duration(seconds: 10));
      expect(
        !(await r.controller.checkOutcome(result.operationId)).terminal,
        'Restart breaks interval',
      );
      r.clock = r.clock.add(const Duration(seconds: 10));
      expect(
        (await r.controller.checkOutcome(result.operationId)).terminal,
        'Fresh post-restart interval completes',
      );
    });
    for (final defect in [
      'missing_source',
      'target_changed',
      'target_binding',
      'worker_alive',
    ]) {
      await test('$defect prevents completion', (r) async {
        final result = await r.controller.confirmAndStart(r.plan());
        r.missingRouter = defect == 'missing_source';
        r.targetChanged = defect == 'target_changed';
        r.wrongTarget = defect == 'target_binding';
        r.workerTerminated = defect != 'worker_alive';
        r.clock = r.clock.add(const Duration(seconds: 310));
        await r.controller.checkOutcome(result.operationId);
        r.clock = r.clock.add(const Duration(seconds: 10));
        expect(
          !(await r.controller.checkOutcome(result.operationId)).terminal,
          'Incomplete outcome cannot release global fence',
        );
      });
    }
    await test('stop wins against an already pending observation callback', (
      r,
    ) async {
      final result = await r.controller.confirmAndStart(r.plan());
      r.clock = r.clock.add(const Duration(seconds: 310));
      r.observeHold = Completer<void>();
      final observing = r.controller.checkOutcome(result.operationId);
      while (r.observationCalls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await r.controller.stopObservation(result.operationId);
      r.observeHold!.complete();
      expect(
        (await observing).stage == MoveStage.observationStopped,
        'Late callback must not resume',
      );
      expect(
        (await r.controller.checkOutcome(result.operationId)).stage ==
            MoveStage.observationStopped,
        'Explicit resume required',
      );
    });
    for (final boundary in ['before_worker', 'after_worker']) {
      await test(
        'real process exit $boundary restores uncertainty without replay',
        (r) async {
          final journal = r.journal as NativeMoveJournal;
          final result = await Process.run(Platform.resolvedExecutable, [
            Platform.script.toFilePath(),
            '--child',
            helper,
            journal.directory,
            boundary,
          ]);
          expect(
            result.exitCode == 73,
            'Expected deliberate process exit; stderr: ${result.stderr}',
          );
          final restored = await r.controller.restore();
          expect(
            restored?.disposition == MoveDisposition.uncertain,
            'Restart must be uncertain',
          );
          await failure(
            r.controller.confirmAndStart(r.plan(id: '2')),
            'unresolved_operation',
          );
          expect(r.calls == 0, 'Restart cannot invoke worker');
          expect(
            await File('${journal.directory}/synthetic_calls').exists() ==
                (boundary == 'after_worker'),
            'Fault boundary invocation marker',
          );
        },
      );
    }
    await test('controller initialized empty adopts later external operation', (
      r,
    ) async {
      expect(await r.controller.current() == null, 'Starts empty');
      final journal = r.journal as NativeMoveJournal;
      final seeded = await Process.run(Platform.resolvedExecutable, [
        Platform.script.toFilePath(),
        '--restart-observation',
        helper,
        journal.directory,
        'accepted',
        'seed',
        'checkOutcome',
      ]);
      expect(seeded.exitCode == 0, 'External seed failed: ${seeded.stderr}');
      r.clock = r.clock.add(const Duration(seconds: 320));
      expect(
        !(await r.controller.checkOutcome(hex('a'))).terminal,
        'Unfamiliar operation cannot inherit external continuity',
      );
      r.clock = r.clock.add(const Duration(seconds: 10));
      expect(
        (await r.controller.checkOutcome(hex('a'))).terminal,
        'Adopted operation retains its fresh interval',
      );
    });
    for (final disposition in ['accepted', 'uncertain', 'rejected']) {
      for (final entry in ['current', 'checkOutcome']) {
        await test(
          'real restart $disposition via $entry needs a fresh interval',
          (r) async {
            final journal = r.journal as NativeMoveJournal;
            for (final phase in ['seed', 'recover']) {
              final result = await Process.run(Platform.resolvedExecutable, [
                Platform.script.toFilePath(),
                '--restart-observation',
                helper,
                journal.directory,
                disposition,
                phase,
                entry,
              ]);
              expect(
                result.exitCode == 0,
                '$phase process failed: ${result.stdout} ${result.stderr}',
              );
            }
          },
        );
      }
    }
    await test('journal has commitments and no private request material', (
      r,
    ) async {
      await r.controller.confirmAndStart(r.plan());
      final text = (await r.journal.read())!.encode();
      expect(
        !text.contains('dataset=') &&
            !text.contains('endpoint=') &&
            !text.contains('pskc=') &&
            !text.contains('network_name='),
        'No secret request fields',
      );
      expect(
        MoveRecord.decode(text).encode() == text,
        'Canonical bounded record',
      );
    });
    stdout.writeln(
      '$count standalone execution checks passed. No network mutation was performed.',
    );
  } finally {
    await parent.delete(recursive: true);
  }
}
