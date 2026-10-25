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
  final Set<String> _expandedRouters = {};

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
            title: const Text('Import network credentials'),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Paste a dataset you are authorized to use. It stays in memory for this session.'),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('live-dataset-input'),
                    controller: controller,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'Dataset hex (advanced)'),
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
    if (probe == null) return 'Not checked';
    if (probe.verified) return 'Verified · network matches';
    if (probe.identityMatch == 'mismatch') return 'Different network';
    if (probe.probeStatus == 'timeout') return 'Check timed out';
    if (probe.probeStatus == 'unsupported') return 'Check unavailable';
    if (probe.probeStatus == 'error') return 'Check failed';
    return 'Check incomplete';
  }

  String _probeDetail(LiveProbe? probe) {
    if (probe == null) return 'No authenticated read yet.';
    if (probe.verified) {
      return 'Authenticated read completed and the imported network identity matches.';
    }
    if (probe.identityMatch == 'mismatch') {
      return 'The read reported a different network identity. Do not treat this router as part of the imported network.';
    }
    if (probe.probeStatus == 'timeout') {
      return 'The read timed out. Authentication and network identity remain unverified.';
    }
    if (probe.probeStatus == 'unsupported') {
      return 'The helper or router does not support this read.';
    }
    if (probe.probeStatus == 'error') {
      return 'The read failed. Network identity remains unverified.';
    }
    return probe.authenticated == true
        ? 'Authentication succeeded, but the read was incomplete. The network is not verified.'
        : 'The read was incomplete. Authentication and network identity remain unverified.';
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              children: [
                Row(children: [
                  Expanded(
                    child: Text('Thread Network Tool',
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  IconButton(
                    key: const Key('live-report'),
                    tooltip: 'Redacted report',
                    onPressed: state == null ? null : _showReport,
                    icon: const Icon(Icons.description_outlined),
                  ),
                ]),
                const SizedBox(height: 5),
                Wrap(
                  key: const Key('live-banner'),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Icon(Icons.visibility_outlined,
                        size: 18, color: colors.primary),
                    const Text('Live · Read only'),
                    const Text('No network changes'),
                  ],
                ),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(key: Key('live-busy')),
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  Text(_notice!,
                      key: const Key('live-error'),
                      style: TextStyle(color: colors.error)),
                ],
                Text(_nextAction(state),
                    key: const Key('live-next-action'),
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
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
                      icon: const Icon(Icons.search),
                      label: const Text('Find routers'),
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
                  ],
                ),
                const SizedBox(height: 18),
                if (state == null)
                  const Text('Waiting for the local helper.')
                else ...[
                  if (state.discoveryStatus == 'unsupported')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Live discovery is unavailable on this device. Check the local helper or platform support.',
                        key: Key('live-unsupported'),
                      ),
                    ),
                  Text('Routers (${state.routers.length})',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 3),
                  Text(_discoverySummary(state),
                      key: const Key('live-discovery-status')),
                  Text(
                    state.credentialAvailable
                        ? 'Credentials ready for ${state.credentialNetworkName ?? 'your network'}'
                        : 'Import credentials to check a router.',
                    key: const Key('live-credentials-status'),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < state.routers.length; i++)
                    _routerCard(state.routers[i], i, state.credentialAvailable),
                  if (state.routers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No routers found. Try Find routers again.'),
                    ),
                  const SizedBox(height: 14),
                  ExpansionTile(
                    key: const Key('live-how-it-works'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('How this works'),
                    children: [
                      const Text(
                          'Router advertisements only suggest a network name. A router is verified only after an authenticated read completes and its identity matches imported credentials. This screen cannot change your network.'),
                      Text(
                          'Discovery observed: ${_localTime(state.observedAt)}',
                          key: const Key('live-observed-at')),
                      Text(
                          'Discovery time (UTC): ${state.observedAt?.toUtc().toIso8601String() ?? 'not yet'}'),
                      Text('Discovery code: ${state.discoveryStatus}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('live-join-disabled'),
                    onPressed: null,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Join router · unavailable'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _localTime(DateTime? value) {
    if (value == null) return 'not yet';
    return TimeOfDay.fromDateTime(value.toLocal()).format(context);
  }

  String _discoverySummary(LiveState state) {
    final time =
        state.observedAt == null ? '' : ' · ${_localTime(state.observedAt)}';
    switch (state.discoveryStatus) {
      case 'completed':
        return 'Search complete$time · advertisements are unverified';
      case 'partial':
        return 'Search incomplete$time · some routers may be missing';
      case 'error':
        return 'Search failed$time · try again';
      case 'unsupported':
        return 'Search unavailable';
      default:
        return 'Search has not run yet';
    }
  }

  String _nextAction(LiveState? state) {
    if (state == null) return 'Connecting to the local helper…';
    if (state.discoveryStatus == 'unsupported') {
      return 'Live checks are unavailable here.';
    }
    if (state.routers.isEmpty) {
      return 'Find border routers on your local network.';
    }
    if (!state.credentialAvailable) {
      return 'Import credentials, then check a router.';
    }
    if (state.routers.any((router) => router.probe?.verified == true)) {
      return 'A router matches your imported network. Check others individually.';
    }
    return 'Choose a router to check against your imported network.';
  }

  Widget _routerCard(LiveRouter router, int index, bool credentialAvailable) {
    final probe = router.probe;
    final colors = Theme.of(context).colorScheme;
    final expanded = _expandedRouters.contains(router.id);
    final statusIcon = probe?.verified == true
        ? Icons.verified_outlined
        : probe?.identityMatch == 'mismatch'
            ? Icons.warning_amber_outlined
            : probe == null
                ? Icons.help_outline
                : Icons.info_outline;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(router.serviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('Advertised: ${router.networkName ?? 'unknown'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                key: Key('live-details-$index'),
                tooltip: expanded ? 'Hide router details' : 'Router details',
                onPressed: () => setState(() {
                  if (expanded) {
                    _expandedRouters.remove(router.id);
                  } else {
                    _expandedRouters.add(router.id);
                  }
                }),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Icon(statusIcon, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(_probeSummary(probe),
                      key: Key('live-probe-status-$index'))),
              const SizedBox(width: 6),
              OutlinedButton(
                key: Key('live-read-$index'),
                onPressed: _busy ||
                        !credentialAvailable ||
                        !router.endpointUsable
                    ? null
                    : () =>
                        _run(() => _api.probe(router.id), routerId: router.id),
                child: _busyRouter == router.id
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Check'),
              ),
            ]),
            if (!router.endpointUsable)
              const Text('No usable address was advertised for this router.'),
            if (expanded) ...[
              const SizedBox(height: 8),
              Text(router.serviceName, key: Key('live-full-name-$index')),
              Text(_probeDetail(probe)),
              Text('Thread version: ${router.threadVersion ?? 'unknown'}'),
              Text(
                  'Endpoint: ${router.endpointUsable ? 'available' : 'unavailable'}'),
              if (probe != null) ...[
                Text('Read code: ${probe.probeStatus}'),
                Text('Active read: ${probe.activeStatus}'),
                Text('Pending read: ${probe.pendingStatus}'),
                Text('Read checked: ${_localTime(probe.checkedAt)}',
                    key: Key('live-checked-at-$index')),
                Text(
                    'Read time (UTC): ${probe.checkedAt.toUtc().toIso8601String()}'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
