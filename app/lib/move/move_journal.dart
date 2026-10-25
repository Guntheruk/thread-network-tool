import 'move_execution.dart';

abstract interface class MoveJournal {
  Future<MoveRecord?> read();
  Future<MoveRecord> begin(MoveRecord record);
  Future<MoveRecord> update(MoveRecord record, int expectedRevision);
}
