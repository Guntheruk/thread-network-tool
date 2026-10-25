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
  });

  final String id;
  final String serviceName;
  final String? networkName;
  final String? threadVersion;
  final bool endpointUsable;
  final LiveProbe? probe;

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
    );
  }
}

class LiveState {
  const LiveState({
    required this.credentialAvailable,
    required this.credentialNetworkName,
    required this.discoveryStatus,
    required this.observedAt,
    required this.routers,
  });

  final bool credentialAvailable;
  final String? credentialNetworkName;
  final String discoveryStatus;
  final DateTime? observedAt;
  final List<LiveRouter> routers;

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
    );
  }
}

abstract class LiveApi {
  Future<LiveState> state();
  Future<LiveState> discover();
  Future<LiveState> credentials(String dataset);
  Future<LiveState> probe(String routerId);
}

class HttpLiveApi implements LiveApi {
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
}
