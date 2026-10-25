import 'dart:convert';
import 'dart:io';

import 'native_inspector.dart';

// Entirely synthetic fixture. This program never contacts a network.
String fixture() {
  final bytes = <int>[];
  void field(int tag, List<int> value) =>
      bytes.addAll([tag, value.length, ...value]);
  field(0, [0, 0, 15]);
  field(1, [0x12, 0x34]);
  field(2, [1, 2, 3, 4, 5, 6, 7, 8]);
  field(3, utf8.encode('TestMesh'));
  field(4, List.filled(16, 0xaa));
  field(5, List.filled(16, 0xbb));
  field(7, [0xfd, 0, 0, 0, 0, 0, 0, 1]);
  field(12, [0, 1, 0xff, 0xf8]);
  field(14, [0, 0, 0, 0, 0, 1, 0, 0]);
  field(53, [0, 4, 0, 0x1f, 0xff, 0xe0]);
  return bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/ffi_smoke.dart <native-library-path>');
    exitCode = 2;
    return;
  }
  final engine = NativeDatasetInspector(args.single);
  final valid = await engine.inspectDataset(fixture());
  final invalid = await engine.inspectDataset('not-a-dataset');
  final duplicate = await engine.inspectDataset('${fixture()}01021234');
  if (!valid.accepted ||
      valid.metadata?.networkName != 'TestMesh' ||
      valid.metadata?.channel != 15 ||
      invalid.accepted ||
      duplicate.accepted) {
    stderr
        .writeln('Native Dart binding verification failed; input suppressed.');
    exitCode = 1;
    return;
  }
  stdout.writeln(
      'Native Dart binding passed: valid metadata, invalid input, duplicate TLV.');
}
