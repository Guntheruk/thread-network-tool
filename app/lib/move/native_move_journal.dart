import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'move_execution.dart';
import 'move_journal.dart';

/// Uses the separately packaged native helper for real process locks and
/// fsync(file + directory). Dart flush/rename is not used as a durability claim.
/// Parent directory must already exist; the helper creates only its private
/// final directory. The path/executable are supplied by native app packaging.
class NativeMoveJournal implements MoveJournal {
  const NativeMoveJournal({required this.executable, required this.directory});
  final String executable;
  final String directory;

  Future<void> initialize() async {
    if (await _call('initialize') != 'ready\n') {
      throw const MoveExecutionFailure('journal_unavailable');
    }
  }

  @override
  Future<MoveRecord?> read() async {
    final result = await _call('read');
    return result == 'empty\n' ? null : MoveRecord.decode(result);
  }

  @override
  Future<MoveRecord> begin(MoveRecord record) async =>
      MoveRecord.decode(await _call('begin', record: record));

  @override
  Future<MoveRecord> update(MoveRecord record, int expectedRevision) async =>
      MoveRecord.decode(
        await _call(
          'update',
          record: record,
          expectedRevision: expectedRevision,
        ),
      );

  Future<String> _call(
    String action, {
    MoveRecord? record,
    int? expectedRevision,
  }) async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw const MoveExecutionFailure('journal_platform_unsupported');
    }
    Process? process;
    Timer? timer;
    var invalid = false;
    try {
      process = await Process.start(executable, [
        action,
        directory,
        if (expectedRevision != null) '$expectedRevision',
      ], runInShell: false);
      final child = process;
      final bytes = <int>[];
      var errors = 0;
      final outputDone = child.stdout.listen((chunk) {
        if (bytes.length + chunk.length > 8192) {
          invalid = true;
          child.kill(ProcessSignal.sigkill);
        } else {
          bytes.addAll(chunk);
        }
      }).asFuture<void>();
      final errorDone = child.stderr.listen((chunk) {
        errors += chunk.length;
        if (errors > 8192) {
          invalid = true;
          child.kill(ProcessSignal.sigkill);
        }
      }).asFuture<void>();
      timer = Timer(const Duration(seconds: 10), () {
        invalid = true;
        child.kill(ProcessSignal.sigkill);
      });
      if (record != null) child.stdin.write(record.encode());
      await child.stdin.close();
      final code = await child.exitCode;
      await Future.wait([outputDone, errorDone]);
      if (invalid) throw const MoveExecutionFailure('journal_unavailable');
      final result = utf8.decode(bytes);
      if (code != 0) {
        const known = {
          'journal_busy\n',
          'unresolved_operation\n',
          'operation_already_exists\n',
        };
        throw MoveExecutionFailure(
          known.contains(result) ? result.trim() : 'journal_unavailable',
        );
      }
      return result;
    } on MoveExecutionFailure {
      rethrow;
    } catch (_) {
      process?.kill(ProcessSignal.sigkill);
      throw const MoveExecutionFailure('journal_unavailable');
    } finally {
      timer?.cancel();
    }
  }
}
