import 'dart:convert';

import 'package:http/http.dart' as http;

class LiveApiException implements Exception {
  const LiveApiException();
}

String _safeText(Object? value, {int maxBytes = 128}) {
  if (value is! String ||
      value.isEmpty ||
      utf8.encode(value).length > maxBytes ||
      value.runes.any((r) => r < 0x20 || r == 0x7f)) {
    throw const FormatException('Invalid live state');
  }
  return value;
}

String? _optionalText(Object? value, {int maxBytes = 128}) =>
    value == null ? null : _safeText(value, maxBytes: maxBytes);

String _choice(Object? value, Set<String> allowed) {
  if (value is! String || !allowed.contains(value)) {
    throw const FormatException('Invalid live state');
  }
  return value;
}

class LiveProbe {
  const LiveProbe({
    required this.probeStatus,
    required this.authenticated,
    required this.identityMatch,
    required this.activeStatus,
    required this.pendingStatus,
    required this.checkedAt,
  });

  final String probeStatus;
  final Object authenticated;
  final String? identityMatch;
  final String activeStatus;
  final String pendingStatus;
  final DateTime checkedAt;

  bool get verified =>
      probeStatus == 'completed' &&
      authenticated == true &&
      identityMatch == 'match' &&
      activeStatus == 'read' &&
      (pendingStatus == 'empty' || pendingStatus == 'present');

  factory LiveProbe.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid live state');
    }
    final authenticated = value['authenticated'];
    if (authenticated is! bool && authenticated != 'unknown') {
      throw const FormatException('Invalid live state');
    }
    final identity = value['identity_match'];
    if (identity != null &&
        identity != 'match' &&
        identity != 'mismatch' &&
        identity != 'unknown') {
      throw const FormatException('Invalid live state');
    }
    final checked = DateTime.tryParse(_safeText(value['checked_at']));
    if (checked == null) throw const FormatException('Invalid live state');
    return LiveProbe(
      probeStatus: _choice(value['probe_status'], const {
        'completed',
        'partial',
        'error',
        'timeout',
        'unsupported',
      }),
      authenticated: authenticated,
      identityMatch: identity as String?,
      activeStatus: _choice(value['active_status'], const {
        'read',
        'error',
        'unknown',
      }),
      pendingStatus: _choice(value['pending_status'], const {
        'empty',
        'present',
        'error',
        'unknown',
      }),
      checkedAt: checked,
    );
  }
}

class LiveRouter {
  const LiveRouter({
    required this.id,
    required this.serviceName,
    required this.networkName,
    required this.threadVersion,
    required this.endpointUsable,
    required this.probe,
    this.roleProbes = const {},
  });

  final String id;
  final String serviceName;
  final String? networkName;
  final String? threadVersion;
  final bool endpointUsable;
  final LiveProbe? probe;
  final Map<String, LiveProbe> roleProbes;

  factory LiveRouter.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['endpoint_usable'] is! bool) {
      throw const FormatException('Invalid live state');
    }
    return LiveRouter(
      id: _safeText(value['id']),
      serviceName: _safeText(value['service_name'], maxBytes: 255),
      networkName: _optionalText(value['network_name'], maxBytes: 16),
      threadVersion: _optionalText(value['thread_version'], maxBytes: 32),
      endpointUsable: value['endpoint_usable'] as bool,
      probe: value['probe'] == null ? null : LiveProbe.fromJson(value['probe']),
      roleProbes: _roleProbes(value['role_probes']),
    );
  }

  static Map<String, LiveProbe> _roleProbes(Object? value) {
    if (value == null) return const {};
    if (value is! Map<String, dynamic> ||
        value.keys.any((key) => key != 'source' && key != 'target')) {
      throw const FormatException('Invalid live state');
    }
    return Map.unmodifiable(
        value.map((key, item) => MapEntry(key, LiveProbe.fromJson(item))));
  }
}

class LiveState {
  const LiveState({
    required this.credentialAvailable,
    required this.credentialNetworkName,
    required this.discoveryStatus,
    required this.observedAt,
    required this.routers,
    this.sourceCredentialAvailable = false,
    this.sourceCredentialNetworkName,
    this.targetCredentialAvailable = false,
    this.targetCredentialNetworkName,
  });

  final bool credentialAvailable;
  final String? credentialNetworkName;
  final String discoveryStatus;
  final DateTime? observedAt;
  final List<LiveRouter> routers;
  final bool sourceCredentialAvailable;
  final String? sourceCredentialNetworkName;
  final bool targetCredentialAvailable;
  final String? targetCredentialNetworkName;

  factory LiveState.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['schema_version'] != 1 ||
        value['mode'] != 'live' ||
        value['credential_available'] is! bool ||
        value['routers'] is! List) {
      throw const FormatException('Invalid live state');
    }
    final timestamp = value['observed_at'];
    final observedAt =
        timestamp == null ? null : DateTime.tryParse(_safeText(timestamp));
    if (timestamp != null && observedAt == null) {
      throw const FormatException('Invalid live state');
    }
    final routers = (value['routers'] as List)
        .map(LiveRouter.fromJson)
        .toList(growable: false);
    if (routers.map((r) => r.id).toSet().length != routers.length) {
      throw const FormatException('Invalid live state');
    }
    return LiveState(
      credentialAvailable: value['credential_available'] as bool,
      credentialNetworkName: _optionalText(value['credential_network_name']),
      discoveryStatus: _choice(value['discovery_status'], const {
        'idle',
        'completed',
        'partial',
        'error',
        'unsupported',
      }),
      observedAt: observedAt,
      routers: routers,
      sourceCredentialAvailable:
          _optionalBool(value['source_credential_available']),
      sourceCredentialNetworkName:
          _optionalText(value['source_credential_network_name'], maxBytes: 16),
      targetCredentialAvailable:
          _optionalBool(value['target_credential_available']),
      targetCredentialNetworkName:
          _optionalText(value['target_credential_network_name'], maxBytes: 16),
    );
  }

  static bool _optionalBool(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    throw const FormatException('Invalid live state');
  }
}

class EmptySourceAttestationInput {
  const EmptySourceAttestationInput({required this.attestedAt});
  final DateTime attestedAt;

  Map<String, Object> toJson() => {
        'method': 'operator_controlled_inventory',
        'scope': 'whole_source_network',
        'attested_at': attestedAt.toUtc().toIso8601String(),
      };
}

class NetworkMoveSourceRouter {
  const NetworkMoveSourceRouter(
      this.routerId, this.serviceName, this.readCheckedAt, this.readStatus);
  final String routerId;
  final String serviceName;
  final DateTime? readCheckedAt;
  final String readStatus;

  factory NetworkMoveSourceRouter.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid plan');
    }
    final checked = value['read_checked_at'];
    final time = checked == null ? null : DateTime.tryParse(_safeText(checked));
    if (checked != null && time == null) {
      throw const FormatException('Invalid plan');
    }
    return NetworkMoveSourceRouter(
      _safeText(value['router_id']),
      _safeText(value['service_name'], maxBytes: 255),
      time,
      _choice(value['read_status'], const {
        'not_checked',
        'completed',
        'partial',
        'error',
        'timeout',
        'unsupported'
      }),
    );
  }
}

class NetworkMovePlan {
  const NetworkMovePlan(
      {required this.decision,
      required this.blockers,
      required this.reviewId,
      required this.reviewValidUntil,
      required this.sourceRouters,
      required this.targetRouterId,
      required this.targetReadCheckedAt,
      required this.delaySeconds,
      required this.verification,
      required this.recovery});
  final String decision;
  final List<String> blockers;
  final String reviewId;
  final DateTime reviewValidUntil;
  final List<NetworkMoveSourceRouter> sourceRouters;
  final String targetRouterId;
  final DateTime? targetReadCheckedAt;
  final int delaySeconds;
  final String verification;
  final String recovery;
  bool get readyForLabReview => decision == 'ready_for_lab_review';
  String get affectedScope => 'whole_source_network';
  bool get unknownOfflineDevices => true;
  bool get inventoryComplete => false;

  factory NetworkMovePlan.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['schema_version'] != 1 ||
        value['mode'] != 'network_move_review' ||
        value['affected_scope'] != 'whole_source_network' ||
        value['unknown_offline_devices'] != true ||
        value['inventory_complete'] != false ||
        value['blockers'] is! List ||
        value['source_routers'] is! List ||
        value['delay_seconds'] is! int) {
      throw const FormatException('Invalid plan');
    }
    final expires = DateTime.tryParse(_safeText(value['review_valid_until']));
    if (expires == null) throw const FormatException('Invalid plan');
    final targetChecked = value['target_read_checked_at'];
    final targetTime = targetChecked == null
        ? null
        : DateTime.tryParse(_safeText(targetChecked));
    if (targetChecked != null && targetTime == null) {
      throw const FormatException('Invalid plan');
    }
    final blockers = (value['blockers'] as List)
        .map((e) => _safeText(e))
        .toList(growable: false);
    final routers = (value['source_routers'] as List)
        .map(NetworkMoveSourceRouter.fromJson)
        .toList(growable: false);
    if (routers.map((e) => e.routerId).toSet().length != routers.length) {
      throw const FormatException('Invalid plan');
    }
    return NetworkMovePlan(
      decision: _choice(
          value['decision'], const {'ready_for_lab_review', 'needs_evidence'}),
      blockers: blockers,
      reviewId: _safeText(value['review_id']),
      reviewValidUntil: expires,
      sourceRouters: routers,
      targetRouterId: _safeText(value['target_router_id']),
      targetReadCheckedAt: targetTime,
      delaySeconds: value['delay_seconds'] as int,
      verification: _safeText(value['verification'], maxBytes: 256),
      recovery: _safeText(value['recovery'], maxBytes: 256),
    );
  }
}

abstract class LiveApi {
  Future<LiveState> state();
  Future<LiveState> discover();
  Future<LiveState> credentials(String dataset);
  Future<LiveState> probe(String routerId);
}

abstract class NetworkMoveApi implements LiveApi {
  Future<LiveState> credentialsForRole(String role, String dataset);
  Future<LiveState> probeForRole(String role, String routerId);
  Future<NetworkMovePlan> networkMovePlan(
      {required String targetRouterId,
      required EmptySourceAttestationInput attestation,
      required int delaySeconds});
  Future<NetworkMovePlan?> currentNetworkMovePlan();
}

class HttpLiveApi implements NetworkMoveApi {
  HttpLiveApi(
      {required String session, required Uri baseUri, http.Client? client})
      : assert(RegExp(r'^[0-9a-f]{64}$').hasMatch(session)),
        _session = session,
        _baseUri = baseUri,
        _client = client ?? http.Client();

  final String _session;
  final Uri _baseUri;
  final http.Client _client;

  Future<LiveState> _request(String method, String path, [Object? body]) async {
    final uri = _baseUri.resolve(path);
    if (uri.origin != _baseUri.origin) throw const LiveApiException();
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $_session'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _client.send(request);
      if (streamed.statusCode != 200) throw const LiveApiException();
      final response = await http.Response.fromStream(streamed);
      return LiveState.fromJson(jsonDecode(response.body));
    } catch (_) {
      throw const LiveApiException();
    }
  }

  Future<Object?> _planRequest(String method, String path,
      [Object? body]) async {
    final uri = _baseUri.resolve(path);
    if (uri.origin != _baseUri.origin) throw const LiveApiException();
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $_session'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _client.send(request);
      if (streamed.statusCode != 200) throw const LiveApiException();
      final response = await http.Response.fromStream(streamed);
      return jsonDecode(response.body);
    } catch (_) {
      throw const LiveApiException();
    }
  }

  @override
  Future<LiveState> state() => _request('GET', '/api/state');

  @override
  Future<LiveState> discover() =>
      _request('POST', '/api/discover', <String, Object>{});

  @override
  Future<LiveState> credentials(String dataset) =>
      _request('POST', '/api/credentials', {'dataset': dataset});

  @override
  Future<LiveState> probe(String routerId) =>
      _request('POST', '/api/probe', {'router_id': routerId});

  @override
  Future<LiveState> credentialsForRole(String role, String dataset) =>
      _request('POST', '/api/credentials', {'role': role, 'dataset': dataset});

  @override
  Future<LiveState> probeForRole(String role, String routerId) =>
      _request('POST', '/api/probe', {'role': role, 'router_id': routerId});

  @override
  Future<NetworkMovePlan> networkMovePlan(
          {required String targetRouterId,
          required EmptySourceAttestationInput attestation,
          required int delaySeconds}) async =>
      NetworkMovePlan.fromJson(
          await _planRequest('POST', '/api/network-move/plan', {
        'target_router_id': targetRouterId,
        'empty_source_attestation': attestation.toJson(),
        'delay_seconds': delaySeconds,
      }));

  @override
  Future<NetworkMovePlan?> currentNetworkMovePlan() async {
    final response = await _planRequest('GET', '/api/network-move/plan');
    if (response is! Map<String, dynamic> || !response.containsKey('plan')) {
      throw const LiveApiException();
    }
    return response['plan'] == null
        ? null
        : NetworkMovePlan.fromJson(response['plan']);
  }
}
