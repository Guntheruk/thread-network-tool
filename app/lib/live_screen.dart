import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'live_api.dart';

String liveReport(LiveState state) {
  final attempted = state.routers.where((r) => r.probe != null).length;
  final verified = state.routers.where((r) => r.probe?.verified == true).length;
  final mismatched =
      state.routers.where((r) => r.probe?.identityMatch == 'mismatch').length;
  final timedOut =
      state.routers.where((r) => r.probe?.probeStatus == 'timeout').length;
  return [
    'Thread Network Tool — read-only live assessment',
    'Discovery status: ${state.discoveryStatus}',
    'Advertised routers: ${state.routers.length} (unverified advertisements)',
    'Credentials available: ${state.credentialAvailable ? 'yes' : 'no'}',
    'Router reads attempted: $attempted',
    'Authenticated identity matches: $verified',
    'Identity mismatches: $mismatched',
    'Read timeouts: $timedOut',
    'Joining: disabled pending compatible router and lab validation',
    'Network names, device IDs, endpoints and credentials: excluded',
  ].join('\n');
}

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, this.session, this.api})
      : assert(session != null || api != null);

  final String? session;
  final LiveApi? api;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  late final LiveApi _api;
  LiveState? _state;
  bool _busy = true;
  String? _busyRouter;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _api =
        widget.api ?? HttpLiveApi(session: widget.session!, baseUri: Uri.base);
    _run(_api.state);
  }

  Future<void> _run(Future<LiveState> Function() operation,
      {String? routerId}) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _busyRouter = routerId;
      _notice = null;
    });
    try {
      final next = await operation().timeout(const Duration(seconds: 38));
      if (mounted) setState(() => _state = next);
    } catch (_) {
      if (mounted) {
        setState(() => _notice =
            'The local helper could not complete this request. Refresh discovery if the router list expired.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyRouter = null;
        });
      }
    }
  }

  Future<void> _importCredentials() async {
    final controller = TextEditingController();
    var submitting = false;
    var failed = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            title: const Text('Import authorized credentials'),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Dataset stays in helper memory for this session. Input is masked.'),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('live-dataset-input'),
                    controller: controller,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Dataset hex'),
                  ),
                  if (failed) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Credential import failed. Check the dataset and try again.',
                      key: Key('live-import-error'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    submitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('live-import-submit'),
                onPressed: submitting
                    ? null
                    : () async {
                        final input = controller.text;
                        controller.clear();
                        if (input.isEmpty || input.length > 508) {
                          updateDialog(() => failed = true);
                          return;
                        }
                        updateDialog(() {
                          submitting = true;
                          failed = false;
                        });
                        try {
                          final next = await _api
                              .credentials(input)
                              .timeout(const Duration(seconds: 38));
                          if (!dialogContext.mounted) return;
                          setState(() => _state = next);
                          Navigator.pop(dialogContext);
                        } catch (_) {
                          if (dialogContext.mounted) {
                            updateDialog(() {
                              submitting = false;
                              failed = true;
                            });
                          }
                        }
                      },
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.clear();
      controller.dispose();
    }
  }

  String _probeSummary(LiveProbe? probe) {
    if (probe == null) return 'No authenticated read yet';
    if (probe.verified) {
      return 'Authenticated read · imported network identity matches';
    }
    if (probe.identityMatch == 'mismatch') {
      return 'Identity mismatch · do not treat this router as the imported network';
    }
    if (probe.probeStatus == 'timeout') {
      return 'Read timed out · authentication and identity remain unverified';
    }
    if (probe.probeStatus == 'unsupported') {
      return 'Read unsupported on this helper or router';
    }
    if (probe.authenticated == true) {
      return 'Read incomplete · authenticated, but network identity remains unverified';
    }
    return 'Read incomplete · authentication and identity unverified';
  }

  Future<void> _showReport() async {
    final state = _state;
    if (state == null) return;
    final report = liveReport(state);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redacted live report'),
        content: SizedBox(
          width: 500,
          child: SelectableText(report, key: const Key('live-report-text')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            key: const Key('live-copy-report'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              children: [
                Text('Thread Network Tool',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Card(
                  key: const Key('live-banner'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LIVE · READ ONLY',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 5),
                        const Text(
                            'Local discovery and authorized router reads. Advertisements are unverified until an authenticated read matches imported credentials. Joining remains disabled.'),
                      ],
                    ),
                  ),
                ),
                if (_busy) const LinearProgressIndicator(key: Key('live-busy')),
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  Text(_notice!, key: const Key('live-error')),
                ],
                const SizedBox(height: 15),
                Wrap(
                  spacing: 9,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('live-discover'),
                      onPressed:
                          _busy || state?.discoveryStatus == 'unsupported'
                              ? null
                              : () => _run(_api.discover),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh discovery'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('live-import'),
                      onPressed:
                          _busy || state?.discoveryStatus == 'unsupported'
                              ? null
                              : _importCredentials,
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Import credentials'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('live-report'),
                      onPressed: state == null ? null : _showReport,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Redacted report'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state == null)
                  const Text('Waiting for the local helper.')
                else ...[
                  if (state.discoveryStatus == 'unsupported')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Native helper unavailable or this platform is not supported. Live reads cannot run here.',
                        key: Key('live-unsupported'),
                      ),
                    ),
                  Text(
                      'Discovery: ${state.discoveryStatus} · ${state.routers.length} advertised routers',
                      key: const Key('live-discovery-status')),
                  Text(
                      'Discovery observed: ${state.observedAt?.toUtc().toIso8601String() ?? 'not yet'}',
                      key: const Key('live-observed-at')),
                  const SizedBox(height: 6),
                  Text(
                      state.credentialAvailable
                          ? 'Credentials ready for ${state.credentialNetworkName ?? 'an authorized network'}'
                          : 'No credentials available. Import an authorized dataset to read routers.',
                      key: const Key('live-credentials-status')),
                  const SizedBox(height: 14),
                  for (var i = 0; i < state.routers.length; i++)
                    _routerCard(state.routers[i], i, state.credentialAvailable),
                  if (state.routers.isEmpty)
                    const Card(
                        child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                          'No routers are listed. Refresh discovery to check the local network.'),
                    )),
                  const SizedBox(height: 12),
                  const Card(
                      child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                        'Join router unavailable · compatibility and safe lab joining have not been validated.'),
                  )),
                  FilledButton.icon(
                    key: const Key('live-join-disabled'),
                    onPressed: null,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Join router unavailable'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _routerCard(LiveRouter router, int index, bool credentialAvailable) {
    final probe = router.probe;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(router.serviceName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Advertised network: ${router.networkName ?? 'unknown'} · unverified'),
            Text(
                'Thread version: ${router.threadVersion ?? 'unknown'} · endpoint ${router.endpointUsable ? 'available' : 'unavailable'}'),
            const SizedBox(height: 8),
            Text(_probeSummary(probe), key: Key('live-probe-status-$index')),
            if (probe != null) ...[
              const SizedBox(height: 3),
              Text(
                  'Active read: ${probe.activeStatus} · pending read: ${probe.pendingStatus}'),
              Text('Read checked: ${probe.checkedAt.toUtc().toIso8601String()}',
                  key: Key('live-checked-at-$index')),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: Key('live-read-$index'),
              onPressed: _busy || !credentialAvailable || !router.endpointUsable
                  ? null
                  : () =>
                      _run(() => _api.probe(router.id), routerId: router.id),
              icon: _busyRouter == router.id
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open_outlined),
              label: const Text('Read this router'),
            ),
          ],
        ),
      ),
    );
  }
}
