import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../move/network_move_plan.dart';

typedef NativeCall = Future<NativeReply> Function(List<String>, String?);

class NativeReply {
  const NativeReply(this.exitCode, this.value);
  final int exitCode;
  final Map<String, dynamic> value;
}

/// Each read runs in a bounded child. No shell, credential argv, or raw logs.
class NativeProcess {
  NativeProcess(this.executable, {this.discoveryExecutable});
  final String executable;
  final String? discoveryExecutable;

  Future<NativeReply> call(List<String> arguments, String? credential) async {
    Process? child;
    Timer? deadline;
    var timedOut = false;
    var overflow = false;
    try {
      child = await Process.start(
          arguments.first == 'discover'
              ? discoveryExecutable ?? executable
              : executable,
          arguments,
          runInShell: false);
      final process = child;
      final output = <int>[];
      var errorBytes = 0;
      final outDone = process.stdout.listen((bytes) {
        if (output.length + bytes.length > 65536) {
          overflow = true;
          process.kill(ProcessSignal.sigkill);
        } else {
          output.addAll(bytes);
        }
      }).asFuture<void>();
      final errDone = process.stderr.listen((bytes) {
        errorBytes += bytes.length;
        if (errorBytes > 65536) {
          overflow = true;
          process.kill(ProcessSignal.sigkill);
        }
      }).asFuture<void>();
      deadline =
          Timer(Duration(seconds: arguments.first == 'discover' ? 12 : 35), () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
      });
      if (credential != null) process.stdin.writeln(credential);
      await process.stdin.close();
      final code = await process.exitCode;
      await Future.wait([outDone, errDone]);
      if (timedOut || code == 124) {
        return const NativeReply(
            124, {'schema_version': 1, 'probe_status': 'timeout'});
      }
      if (overflow) throw const FormatException();
      final value = jsonDecode(utf8.decode(output));
      if (value is! Map<String, dynamic> || value['schema_version'] != 1) {
        throw const FormatException();
      }
      return NativeReply(code, value);
    } catch (_) {
      child?.kill(ProcessSignal.sigkill);
      return const NativeReply(
          1, {'schema_version': 1, 'probe_status': 'error'});
    } finally {
      deadline?.cancel();
    }
  }
}

class ApiFailure implements Exception {
  const ApiFailure(this.code, this.status);
  final String code;
  final int status;
}

String randomToken() {
  final random = Random.secure();
  return List.generate(
      32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

String? safeText(Object? value, int maxBytes) {
  if (value is! String ||
      value.isEmpty ||
      utf8.encode(value).length > maxBytes ||
      value.runes.any((r) => r < 32 || r == 127)) {
    return null;
  }
  return value;
}

bool localEndpoint(String value) {
  final address = InternetAddress.tryParse(value);
  if (address == null || address.isLoopback || address.isMulticast) {
    return false;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    if (bytes.last == 255 || bytes.last == 0) return false;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }
  // Link-local IPv6 needs an interface zone, unsupported by the initial probe.
  return (bytes[0] & 0xfe) == 0xfc;
}

class LiveSession {
  LiveSession(this.native, {DateTime Function()? now})
      : now = now ?? DateTime.now;
  final NativeCall native;
  final DateTime Function() now;
  String? _credential;
  String? _credentialName;
  final Map<String, _RoleCredential> _roleCredentials = {};
  final Map<String, Map<String, _RoleRead>> _roleReads = {};
  Map<String, dynamic>? _review;
  DateTime? _reviewExpires;
  String _discoveryStatus = 'idle';
  DateTime? _observed;
  bool _busy = false;
  final Map<String, Map<String, dynamic>> _routers = {};
  final Map<String, (String, int)> _endpoints = {};
  final Map<String, String?> _advertisedXpans = {};
  // Membership learned from authenticated source reads survives later failed
  // reads. It is scoped to this discovery and source credential generation.
  final Set<String> _knownSourceCandidates = {};

  Map<String, dynamic> get state => {
        'schema_version': 1,
        'mode': 'live',
        'credential_available': _credential != null,
        'credential_network_name': _credentialName,
        'source_credential_available': _roleCredentials.containsKey('source'),
        'source_credential_network_name': _roleCredentials['source']?.name,
        'target_credential_available': _roleCredentials.containsKey('target'),
        'target_credential_network_name': _roleCredentials['target']?.name,
        'discovery_status': _discoveryStatus,
        'observed_at': _observed?.toUtc().toIso8601String(),
        'routers': _routers.values
            .map((router) => <String, dynamic>{
                  ...router,
                  'probe': router['probe'] == null
                      ? null
                      : Map<String, dynamic>.from(router['probe'] as Map),
                  'role_probes': (router['role_probes'] as Map<String, dynamic>)
                      .map((role, probe) => MapEntry(
                          role, Map<String, dynamic>.from(probe as Map))),
                })
            .toList(growable: false),
      };

  Future<Map<String, dynamic>> perform(
      String action, Map<String, dynamic> body) async {
    if (_busy) throw const ApiFailure('busy', 409);
    _busy = true;
    try {
      switch (action) {
        case 'credentials':
          await _import(body['dataset'], body['role']);
        case 'discover':
          await _discover();
        case 'probe':
          await _probe(body['router_id'], body['role']);
        case 'network-move/plan':
          return _plan(body);
        default:
          throw const ApiFailure('not_found', 404);
      }
      return state;
    } finally {
      _busy = false;
    }
  }

  Future<void> _import(Object? input, Object? role) async {
    if (role != null && role != 'source' && role != 'target') {
      throw const ApiFailure('invalid_role', 400);
    }
    if (input is! String ||
        input.isEmpty ||
        input.length > 508 ||
        !RegExp(r'^(?:[0-9a-fA-F]{2})+$').hasMatch(input)) {
      throw const ApiFailure('invalid_credentials', 400);
    }
    final result = await native(['inspect'], input);
    final name = safeText(result.value['network_name'], 16);
    if (result.exitCode != 0 || result.value['valid'] != true || name == null) {
      throw const ApiFailure('invalid_credentials', 400);
    }
    if (role == null) {
      _credential = input;
      _credentialName = name;
      for (final router in _routers.values) {
        router['probe'] = null;
      }
    } else {
      final xpan = result.value['extended_pan_id'];
      final channel = result.value['channel'];
      final timestamp = result.value['active_timestamp'];
      if (xpan is! String ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(xpan) ||
          channel is! int ||
          channel < 11 ||
          channel > 26 ||
          timestamp is! String ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(timestamp)) {
        throw const ApiFailure('invalid_credentials', 400);
      }
      _roleCredentials[role as String] = _RoleCredential(
          input, name, xpan, channel, timestamp, randomToken(), now());
      _roleReads.remove(role);
      if (role == 'source') _knownSourceCandidates.clear();
      for (final router in _routers.values) {
        (router['role_probes'] as Map<String, dynamic>).remove(role);
      }
    }
    _invalidateReview();
  }

  Future<void> _discover() async {
    // A fresh scan invalidates both endpoint handles and earlier verification.
    _routers.clear();
    _roleReads.clear();
    _invalidateReview();
    _endpoints.clear();
    _advertisedXpans.clear();
    _knownSourceCandidates.clear();
    _observed = null;
    _discoveryStatus = 'error';
    final result = await native(['discover'], null);
    final status = result.value['discovery_status'];
    if (!{'completed', 'partial', 'error', 'unsupported'}.contains(status)) {
      return;
    }
    _discoveryStatus = status as String;
    _observed = now();
    final rows = result.value['routers'];
    if (rows is! List ||
        rows.length > 256 ||
        !{'completed', 'partial'}.contains(status)) {
      return;
    }
    final candidates = <String, Map>{};
    for (final item in rows) {
      if (item is! Map) continue;
      final name = safeText(item['service_name'], 255);
      final address = item['address'];
      final port = item['port'];
      if (name == null ||
          address is! String ||
          port is! int ||
          port < 1 ||
          port > 65535) {
        continue;
      }
      // DNS-SD instance names are unique within the browsed service/domain.
      // Several interface/address observations are one router, not duplicates.
      final identity = '$name|$port';
      final previous = candidates[identity];
      int score(String address) => !localEndpoint(address)
          ? 0
          : address.contains(':')
              ? 1
              : 2;
      if (previous == null ||
          score(address) > score(previous['address'] as String)) {
        candidates[identity] = item;
      }
    }
    for (final item in candidates.values) {
      final name = item['service_name'] as String;
      final address = item['address'] as String;
      final port = item['port'] as int;
      final id = randomToken();
      final usable = localEndpoint(address);
      _routers[id] = {
        'id': id,
        'service_name': name,
        'network_name': safeText(item['network_name'], 16),
        'thread_version': safeText(item['thread_version'], 32),
        'endpoint_usable': usable,
        'probe': null,
        'role_probes': <String, dynamic>{},
      };
      final advertisedXpan = item['extended_pan_id'];
      _advertisedXpans[id] = advertisedXpan is String &&
              RegExp(r'^[0-9a-f]{16}$').hasMatch(advertisedXpan)
          ? advertisedXpan
          : null;
      if (usable) _endpoints[id] = (address, port);
    }
  }

  Future<void> _probe(Object? id, Object? role) async {
    if (role != null && role != 'source' && role != 'target') {
      throw const ApiFailure('invalid_role', 400);
    }
    final credential =
        role == null ? _credential : _roleCredentials[role]?.dataset;
    if (credential == null) {
      throw const ApiFailure('credentials_required', 409);
    }
    if (_observed == null ||
        now().difference(_observed!) > const Duration(minutes: 5)) {
      throw const ApiFailure('discovery_expired', 409);
    }
    if (id is! String || !_routers.containsKey(id)) {
      throw const ApiFailure('unknown_router', 400);
    }
    final endpoint = _endpoints[id];
    if (endpoint == null) throw const ApiFailure('unsupported_endpoint', 400);
    // Any new observation attempt supersedes older role-bound evidence for
    // this router, including when the native read times out or throws.
    _invalidateReview();
    _roleReads['source']?.remove(id);
    _roleReads['target']?.remove(id);
    (_routers[id]!['role_probes'] as Map<String, dynamic>).clear();
    final response =
        await native(['probe', endpoint.$1, '${endpoint.$2}'], credential);
    final value = response.value;
    final rawStatus = value['probe_status'];
    var status = {'completed', 'partial', 'error', 'timeout', 'unsupported'}
            .contains(rawStatus)
        ? rawStatus as String
        : 'error';
    final authenticated =
        value['authenticated'] is bool ? value['authenticated'] : 'unknown';
    final match =
        {'match', 'mismatch', 'unknown'}.contains(value['identity_match'])
            ? value['identity_match']
            : null;
    final active = {'read', 'error', 'unknown'}.contains(value['active_status'])
        ? value['active_status']
        : 'unknown';
    final pending = {'empty', 'present', 'error', 'unknown'}
            .contains(value['pending_status'])
        ? value['pending_status']
        : 'unknown';
    if (status == 'completed' &&
        (authenticated != true ||
            active != 'read' ||
            !{'match', 'mismatch'}.contains(match) ||
            !{'empty', 'present'}.contains(pending) ||
            (response.exitCode != 0 && match == 'match'))) {
      status = 'partial';
    }
    final publicProbe = <String, dynamic>{
      'probe_status': status,
      'authenticated': authenticated,
      'identity_match': match,
      'active_status': active,
      'pending_status': pending,
      'checked_at': now().toUtc().toIso8601String(),
    };
    if (role == null) {
      _routers[id]!['probe'] = publicProbe;
      return;
    }
    final slot = _roleCredentials[role]!;
    final readName = safeText(value['active_network_name'], 16);
    final readXpan = value['active_extended_pan_id'];
    final readChannel = value['active_channel'];
    final readTimestamp = value['active_timestamp'];
    final identityValid = readName != null &&
        readXpan is String &&
        RegExp(r'^[0-9a-f]{16}$').hasMatch(readXpan) &&
        readChannel is int &&
        readChannel >= 11 &&
        readChannel <= 26;
    final actualMatch = identityValid &&
        readName == slot.name &&
        readXpan == slot.xpan &&
        readChannel == slot.channel;
    final validTimestamp = readTimestamp is String &&
        RegExp(r'^[0-9a-f]{16}$').hasMatch(readTimestamp);
    // A native summary alone cannot attest an identity for planning.
    final planningMatch = match == 'match' && actualMatch;
    if (!planningMatch && match == 'match') {
      publicProbe['identity_match'] = 'unknown';
      publicProbe['probe_status'] = 'partial';
    }
    (_routers[id]!['role_probes'] as Map<String, dynamic>)[role as String] =
        publicProbe;
    _roleReads.putIfAbsent(role, () => {})[id] = _RoleRead(publicProbe,
        planningMatch, validTimestamp ? readTimestamp : null, slot.generation);
    if (role == 'source' &&
        planningMatch &&
        authenticated == true &&
        active == 'read') {
      _knownSourceCandidates.add(id);
    }
  }

  void clear() {
    // Dart strings cannot promise zeroization; secrets are never persisted.
    _credential = null;
    _credentialName = null;
    _roleCredentials.clear();
    _roleReads.clear();
    _invalidateReview();
    _routers.clear();
    _endpoints.clear();
    _advertisedXpans.clear();
    _knownSourceCandidates.clear();
  }

  void _invalidateReview() {
    _review = null;
    _reviewExpires = null;
  }

  Map<String, dynamic>? get currentReview {
    if (_reviewExpires == null || now().isAfter(_reviewExpires!)) {
      _invalidateReview();
    }
    return _review == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(_review)) as Map);
  }

  Map<String, dynamic> _plan(Map<String, dynamic> body) {
    final targetId = body['target_router_id'];
    final delay = body['delay_seconds'];
    if (targetId is! String ||
        !_routers.containsKey(targetId) ||
        delay is! int) {
      throw const ApiFailure('invalid_plan_request', 400);
    }
    final attestationInput = body['empty_source_attestation'];
    EmptySourceAttestation? attestation;
    if (attestationInput is Map) {
      final method = attestationInput['method'];
      final scope = attestationInput['scope'];
      final time = attestationInput['attested_at'];
      if (method is String && scope is String && time is String) {
        final parsed = DateTime.tryParse(time);
        if (parsed != null &&
            parsed.isUtc &&
            time == parsed.toIso8601String()) {
          attestation = EmptySourceAttestation(
              method: method, scope: scope, attestedAt: parsed);
        }
      }
    }
    final source = _roleCredentials['source'];
    final target = _roleCredentials['target'];
    final candidates = _routers.entries.where((entry) {
      final advertisedXpan = _advertisedXpans[entry.key];
      final advertisementSuggestsSource = source != null &&
          (advertisedXpan == source.xpan ||
              (advertisedXpan == null &&
                  entry.value['network_name'] == source.name));
      return advertisementSuggestsSource ||
          _knownSourceCandidates.contains(entry.key);
    }).toList(growable: false);
    final targetRead = _roleReads['target']?[targetId];
    MoveRead? asRead(String role, String id, _RoleRead? value) {
      if (value == null) return null;
      final expectedGeneration = _roleCredentials[role]?.generation;
      if (value.credentialGeneration != expectedGeneration) return null;
      final fields = value.publicProbe;
      return MoveRead(
          routerId: id,
          checkedAt: DateTime.parse(fields['checked_at'] as String),
          matchesRole: value.matchesRole,
          authenticated: fields['authenticated'] == true,
          completed: fields['probe_status'] == 'completed' &&
              fields['active_status'] == 'read',
          pendingEmpty: fields['pending_status'] == 'empty',
          activeTimestamp: value.activeTimestamp);
    }

    final assessment = assessNetworkMove(
      now: now(),
      sourceCredentials: source != null,
      targetCredentials: target != null,
      distinctIdentities: source != null &&
          target != null &&
          (source.name != target.name ||
              source.xpan != target.xpan ||
              source.channel != target.channel),
      discoveryComplete: _discoveryStatus == 'completed' &&
          _observed != null &&
          !now().isBefore(_observed!) &&
          now().difference(_observed!) <= const Duration(minutes: 5),
      sourceReads: candidates
          .map((e) => asRead('source', e.key, _roleReads['source']?[e.key]))
          .toList(),
      targetRead: asRead('target', targetId, targetRead),
      targetIsSource: candidates.any((e) => e.key == targetId),
      attestation: attestation,
      delaySeconds: delay,
    );
    final blockers = <String>{...assessment.blockers};
    if (attestation != null &&
        ((_observed != null && attestation.attestedAt.isBefore(_observed!)) ||
            (source != null &&
                attestation.attestedAt.isBefore(source.importedAt)) ||
            (target != null &&
                attestation.attestedAt.isBefore(target.importedAt)) ||
            candidates.any((entry) {
              final read = _roleReads['source']?[entry.key];
              return read != null &&
                  attestation!.attestedAt.isBefore(
                      DateTime.parse(read.publicProbe['checked_at'] as String));
            }))) {
      blockers.add('empty_source_attestation_stale');
    }
    for (final entry in candidates) {
      final xpan = _advertisedXpans[entry.key];
      if (xpan != null && source != null && xpan != source.xpan) {
        blockers.add('source_advertisement_conflict');
      }
      final read = _roleReads['source']?[entry.key];
      if (read != null &&
          source != null &&
          read.activeTimestamp != null &&
          read.activeTimestamp != source.activeTimestamp) {
        blockers.add('source_timestamp_mismatch');
      }
    }
    if (targetRead != null &&
        target != null &&
        targetRead.activeTimestamp != null &&
        targetRead.activeTimestamp != target.activeTimestamp) {
      blockers.add('target_timestamp_mismatch');
    }
    var expires = now().add(const Duration(minutes: 5));
    void limit(DateTime? evidenceAt) {
      if (evidenceAt == null) return;
      final boundary = evidenceAt.add(const Duration(minutes: 5));
      if (boundary.isBefore(expires)) expires = boundary;
    }

    limit(_observed);
    limit(attestation?.attestedAt);
    limit(targetRead == null
        ? null
        : DateTime.parse(targetRead.publicProbe['checked_at'] as String));
    for (final entry in candidates) {
      final read = _roleReads['source']?[entry.key];
      limit(read == null
          ? null
          : DateTime.parse(read.publicProbe['checked_at'] as String));
    }
    final review = <String, dynamic>{
      'schema_version': 1,
      'mode': 'network_move_review',
      'decision': blockers.isEmpty ? 'ready_for_lab_review' : 'needs_evidence',
      'blockers': blockers.toList(growable: false),
      'review_id': randomToken(),
      'review_valid_until': expires.toUtc().toIso8601String(),
      'affected_scope': 'whole_source_network',
      'source_routers': candidates
          .map((e) => {
                'router_id': e.key,
                'service_name': e.value['service_name'],
                'read_checked_at':
                    _roleReads['source']?[e.key]?.publicProbe['checked_at'],
                'read_status':
                    _roleReads['source']?[e.key]?.publicProbe['probe_status'] ??
                        'not_checked',
              })
          .toList(growable: false),
      'target_router_id': targetId,
      'target_read_checked_at': targetRead?.publicProbe['checked_at'],
      'unknown_offline_devices': true,
      'inventory_complete': false,
      'delay_seconds': delay,
      'verification':
          'Fresh source and target reads after propagation; operational accessory reads if any are present.',
      'recovery': 'Manual recovery; rollback is not guaranteed.',
    };
    _review = review;
    _reviewExpires = expires;
    return currentReview ?? review;
  }
}

class _RoleCredential {
  const _RoleCredential(this.dataset, this.name, this.xpan, this.channel,
      this.activeTimestamp, this.generation, this.importedAt);
  final String dataset;
  final String name;
  final String xpan;
  final int channel;
  final String activeTimestamp;
  final String generation;
  final DateTime importedAt;
}

class _RoleRead {
  const _RoleRead(this.publicProbe, this.matchesRole, this.activeTimestamp,
      this.credentialGeneration);
  final Map<String, dynamic> publicProbe;
  final bool matchesRole;
  final String? activeTimestamp;
  final String credentialGeneration;
}
