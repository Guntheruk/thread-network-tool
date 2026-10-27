import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thread_network_tool/live_api.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

Future<void> main() async {
  final requests = <http.Request>[];
  final api = HttpLiveApi(
    session: 'a' * 64,
    baseUri: Uri.parse('http://127.0.0.1:5188/'),
    client: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/network-move/plan') {
        if (request.method == 'GET') {
          return http.Response(jsonEncode({'plan': null}), 200);
        }
        return http.Response(
            jsonEncode({
              'schema_version': 1,
              'mode': 'network_move_review',
              'decision': 'needs_evidence',
              'blockers': ['source_read_missing_or_stale'],
              'review_id': 'opaque-review',
              'review_valid_until': '2026-10-25T12:05:00.000Z',
              'affected_scope': 'whole_source_network',
              'source_routers': [
                {
                  'router_id': 'opaque-router',
                  'service_name': 'Source A',
                  'read_checked_at': null,
                  'read_status': 'not_checked'
                },
              ],
              'target_router_id': 'opaque-target',
              'target_read_checked_at': null,
              'unknown_offline_devices': true,
              'inventory_complete': false,
              'delay_seconds': 1800,
              'verification': 'Fresh reads',
              'recovery': 'Manual',
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'schema_version': 1,
            'mode': 'live',
            'credential_available': false,
            'source_credential_available': request.body.contains('source'),
            'source_credential_network_name': 'Source',
            'target_credential_available': request.body.contains('target'),
            'target_credential_network_name': 'Target',
            'discovery_status': 'completed',
            'observed_at': '2026-10-25T12:00:00.000Z',
            'routers': [],
          }),
          200);
    }),
  );
  await api.credentialsForRole('source', 'aabb');
  await api.probeForRole('target', 'opaque-target');
  final plan = await api.networkMovePlan(
    targetRouterId: 'opaque-target',
    attestation:
        EmptySourceAttestationInput(attestedAt: DateTime.utc(2026, 10, 25, 12)),
    delaySeconds: 1800,
  );
  check(plan.sourceRouters.length == 1 && !plan.readyForLabReview,
      'typed plan parsing failed');
  check(await api.currentNetworkMovePlan() == null,
      'nullable current plan failed');
  check(
      requests.map((r) => r.url.path).join(',') ==
          '/api/credentials,/api/probe,/api/network-move/plan,/api/network-move/plan',
      'wrong routes');
  check(
      requests.every((r) =>
          r.url.origin == 'http://127.0.0.1:5188' &&
          r.headers['Authorization'] == 'Bearer ${'a' * 64}'),
      'request escaped authenticated origin');
  check(
      jsonDecode(requests[0].body)['role'] == 'source' &&
          jsonDecode(requests[1].body)['role'] == 'target',
      'credential roles lost');
  final posted = jsonDecode(requests[2].body) as Map;
  check(
      posted['target_router_id'] == 'opaque-target' &&
          posted['empty_source_attestation']['scope'] ==
              'whole_source_network' &&
          posted['delay_seconds'] == 1800,
      'plan request malformed');
}
