import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  String _discoveryStatus = 'idle';
  DateTime? _observed;
  bool _busy = false;
  final Map<String, Map<String, dynamic>> _routers = {};
  final Map<String, (String, int)> _endpoints = {};

  Map<String, dynamic> get state => {
        'schema_version': 1,
        'mode': 'live',
        'credential_available': _credential != null,
        'credential_network_name': _credentialName,
        'discovery_status': _discoveryStatus,
        'observed_at': _observed?.toUtc().toIso8601String(),
        'routers': _routers.values.toList(),
      };

  Future<Map<String, dynamic>> perform(
      String action, Map<String, dynamic> body) async {
    if (_busy) throw const ApiFailure('busy', 409);
    _busy = true;
    try {
      switch (action) {
        case 'credentials':
          await _import(body['dataset']);
        case 'discover':
          await _discover();
        case 'probe':
          await _probe(body['router_id']);
        default:
          throw const ApiFailure('not_found', 404);
      }
      return state;
    } finally {
      _busy = false;
    }
  }

  Future<void> _import(Object? input) async {
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
    _credential = input;
    _credentialName = name;
    for (final router in _routers.values) {
      router['probe'] = null;
    }
  }

  Future<void> _discover() async {
    // A fresh scan invalidates both endpoint handles and earlier verification.
    _routers.clear();
    _endpoints.clear();
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
      };
      if (usable) _endpoints[id] = (address, port);
    }
  }

  Future<void> _probe(Object? id) async {
    if (_credential == null) {
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
    final response =
        await native(['probe', endpoint.$1, '${endpoint.$2}'], _credential);
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
    _routers[id]!['probe'] = {
      'probe_status': status,
      'authenticated': authenticated,
      'identity_match': match,
      'active_status': active,
      'pending_status': pending,
      'checked_at': now().toUtc().toIso8601String(),
    };
  }

  void clear() {
    // Dart strings cannot promise zeroization; secrets are never persisted.
    _credential = null;
    _credentialName = null;
    _routers.clear();
    _endpoints.clear();
  }
}
