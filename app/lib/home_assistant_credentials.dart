import 'dart:convert';

import 'home_assistant_credentials_stub.dart'
    if (dart.library.io) 'home_assistant_credentials_io.dart' as platform;

enum HomeAssistantFailure {
  unsupported,
  invalidUrl,
  unencryptedConsentRequired,
  publicHttpRefused,
  connectionFailed,
  authenticationRejected,
  adminRequired,
  threadUnavailable,
  networkNotFound,
  timedOut,
  cancelled,
  invalidData,
  identityMismatch,
}

/// Fixed failures intentionally retain no URL, token, dataset or server message.
class HomeAssistantCredentialException implements Exception {
  const HomeAssistantCredentialException(this.failure);
  final HomeAssistantFailure failure;
  @override
  String toString() => 'HomeAssistantCredentialException(${failure.name})';
}

class HomeAssistantNetwork {
  const HomeAssistantNetwork(
      {required this.id,
      required this.name,
      required this.extendedPanId,
      required this.channel,
      required this.panId});
  final String id;
  final String name;
  final String extendedPanId;
  final int channel;
  final String panId;
}

abstract class HomeAssistantCredentials {
  factory HomeAssistantCredentials(
          {Duration timeout = const Duration(seconds: 15)}) =>
      platform.createHomeAssistantCredentials(timeout);
  bool get supported;
  Future<List<HomeAssistantNetwork>> connectAndList(String url, String token,
      {bool allowUnencrypted = false});
  Future<String> fetchDataset(HomeAssistantNetwork selected);
  void cancel();
}

Never invalidHomeAssistantData() =>
    throw const HomeAssistantCredentialException(
        HomeAssistantFailure.invalidData);

List<HomeAssistantNetwork> decodeHomeAssistantNetworks(Object? result) {
  if (result is! Map || result['datasets'] is! List) invalidHomeAssistantData();
  final rows = result['datasets'] as List;
  if (rows.length > 64) invalidHomeAssistantData();
  final ids = <String>{};
  return List.unmodifiable(rows.map((row) {
    if (row is! Map) invalidHomeAssistantData();
    final id = row['dataset_id'];
    final name = row['network_name'];
    final xpan = row['extended_pan_id'];
    final channel = row['channel'];
    final pan = row['pan_id'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id) ||
        !ids.add(id) ||
        name is! String ||
        name.isEmpty ||
        utf8.encode(name).length > 16 ||
        name.runes.any((c) => c < 32 || c == 127) ||
        xpan is! String ||
        !RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(xpan) ||
        pan is! String ||
        !RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(pan) ||
        channel is! int ||
        channel < 11 ||
        channel > 26) {
      invalidHomeAssistantData();
    }
    return HomeAssistantNetwork(
        id: id,
        name: name,
        extendedPanId: xpan.toLowerCase(),
        channel: channel,
        panId: pan.toLowerCase());
  }));
}

/// Match public identity before handing secrets to the existing full validator.
/// This deliberately does not replace native dataset/policy validation.
String decodeHomeAssistantDataset(
    Object? result, HomeAssistantNetwork selected) {
  if (result is! Map) invalidHomeAssistantData();
  final hex = result['tlv'];
  if (hex is! String ||
      hex.isEmpty ||
      hex.length > 508 ||
      !RegExp(r'^(?:[0-9a-fA-F]{2})+$').hasMatch(hex)) {
    invalidHomeAssistantData();
  }
  final bytes = [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16)
  ];
  final fields = <int, List<int>>{};
  for (var offset = 0; offset < bytes.length;) {
    if (offset + 2 > bytes.length) invalidHomeAssistantData();
    final type = bytes[offset++];
    final size = bytes[offset++];
    if (offset + size > bytes.length || fields.containsKey(type)) {
      invalidHomeAssistantData();
    }
    fields[type] = bytes.sublist(offset, offset + size);
    offset += size;
  }
  final channel = fields[0];
  final xpan = fields[2];
  final name = fields[3];
  final pan = fields[1];
  if (channel == null ||
      channel.length != 3 ||
      channel[0] != 0 ||
      pan == null ||
      pan.length != 2 ||
      xpan == null ||
      xpan.length != 8 ||
      name == null ||
      name.isEmpty ||
      name.length > 16) {
    invalidHomeAssistantData();
  }
  String decodedName;
  try {
    decodedName = utf8.decode(name);
  } catch (_) {
    invalidHomeAssistantData();
  }
  final decodedXpan =
      xpan.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final decodedPan = pan.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  if (decodedPan != selected.panId ||
      decodedName != selected.name ||
      decodedXpan != selected.extendedPanId ||
      (channel[1] << 8 | channel[2]) != selected.channel) {
    throw const HomeAssistantCredentialException(
        HomeAssistantFailure.identityMismatch);
  }
  return hex.toLowerCase();
}
