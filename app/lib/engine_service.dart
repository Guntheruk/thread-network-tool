import 'dart:convert';

/// The Flutter layer only receives inspected metadata. A native implementation
/// may call the C ABI; web/demo never reads or validates real credentials.
abstract class EngineService {
  bool get isSyntheticDemo;

  Future<DatasetInspection> inspectDataset(String datasetHex);
}

class DatasetInspection {
  const DatasetInspection.success(this.metadata) : accepted = true;

  const DatasetInspection.rejected()
      : accepted = false,
        metadata = null;

  final bool accepted;
  final DatasetMetadata? metadata;
}

class DatasetMetadata {
  const DatasetMetadata({
    required this.networkName,
    required this.channel,
    required this.hasNetworkKey,
    required this.hasPskc,
    required this.unknownTlvCount,
  });

  final String networkName;
  final int channel;
  final bool hasNetworkKey;
  final bool hasPskc;
  final int unknownTlvCount;

  /// Accept only the native contract's safe metadata fields. The raw dataset,
  /// network key, PSKc, and native error message are deliberately not modeled.
  factory DatasetMetadata.fromEngineJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 || json['valid'] != true) {
      throw const FormatException('Inspection failed');
    }
    final name = json['network_name'];
    final channel = json['channel'];
    final hasKey = json['has_network_key'];
    final hasPskc = json['has_pskc'];
    final unknown = json['unknown_tlv_types'];
    if (name is! String ||
        name.isEmpty ||
        utf8.encode(name).length > 16 ||
        name.runes.any((rune) => rune < 0x20 || rune == 0x7f) ||
        channel is! int ||
        channel < 11 ||
        channel > 26 ||
        hasKey != true ||
        hasPskc != true ||
        unknown is! List ||
        unknown.any((type) => type is! int || type < 0 || type > 255)) {
      throw const FormatException('Inspection failed');
    }
    return DatasetMetadata(
      networkName: name,
      channel: channel,
      hasNetworkKey: hasKey,
      hasPskc: hasPskc,
      unknownTlvCount: unknown.length,
    );
  }
}

class SyntheticDemoEngineService implements EngineService {
  const SyntheticDemoEngineService();

  @override
  bool get isSyntheticDemo => true;

  @override
  Future<DatasetInspection> inspectDataset(String datasetHex) async {
    // Even well-formed input is rejected: demo is never a credential reader.
    return const DatasetInspection.rejected();
  }

  DatasetInspection inspectSafeFixture() => const DatasetInspection.success(
        DatasetMetadata(
          networkName: 'HomeMesh',
          channel: 15,
          hasNetworkKey: true,
          hasPskc: true,
          unknownTlvCount: 0,
        ),
      );
}
