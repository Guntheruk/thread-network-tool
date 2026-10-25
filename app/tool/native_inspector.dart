import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:thread_network_tool/engine_service.dart';

typedef _InspectC = Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Size);
typedef _InspectDart = int Function(Pointer<Uint8>, Pointer<Uint8>, int);

/// Native parser adapter only. Loading this does not discover or contact routers.
class NativeDatasetInspector implements EngineService {
  NativeDatasetInspector(String libraryPath)
      : _inspect = DynamicLibrary.open(libraryPath)
            .lookupFunction<_InspectC, _InspectDart>('tnt_inspect_dataset');

  final _InspectDart _inspect;

  @override
  bool get isSyntheticDemo => false;

  @override
  Future<DatasetInspection> inspectDataset(String datasetHex) async {
    if (datasetHex.isEmpty ||
        datasetHex.length > 508 ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(datasetHex)) {
      return const DatasetInspection.rejected();
    }
    final input = datasetHex.toNativeUtf8().cast<Uint8>();
    final output = calloc<Uint8>(4096);
    try {
      final result = _inspect(input, output, 4096);
      if (result != 0) return const DatasetInspection.rejected();
      final bytes = output.asTypedList(4096);
      final end = bytes.indexOf(0);
      if (end < 0) return const DatasetInspection.rejected();
      final value = jsonDecode(utf8.decode(bytes.sublist(0, end)));
      if (value is! Map<String, dynamic>) {
        return const DatasetInspection.rejected();
      }
      return DatasetInspection.success(DatasetMetadata.fromEngineJson(value));
    } catch (_) {
      // Do not place provider output or credential input in exceptions/reports.
      return const DatasetInspection.rejected();
    } finally {
      input
          .asTypedList(datasetHex.length + 1)
          .fillRange(0, datasetHex.length + 1, 0);
      output.asTypedList(4096).fillRange(0, 4096, 0);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
