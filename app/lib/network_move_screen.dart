import 'dart:async';

import 'package:flutter/material.dart';

import 'credential_setup_dialog.dart';
import 'live_api.dart';

/// Review and, only for a trusted isolated native capability, explicit move
/// execution. The session revalidates all private evidence before dispatch.
class NetworkMoveScreen extends StatefulWidget {
  const NetworkMoveScreen({
    super.key,
    required this.api,
    required this.initialState,
  });

  final NetworkMoveApi api;
  final LiveState initialState;

  @override
  State<NetworkMoveScreen> createState() => _NetworkMoveScreenState();
}

class _NetworkMoveScreenState extends State<NetworkMoveScreen>
    with WidgetsBindingObserver {
  late LiveState _state = widget.initialState;
  NetworkMovePlan? _plan;
  String? _targetRouterId;
  String? _notice;
  bool _busy = false;
  bool _attested = false;
  int _delaySeconds = 300;
  Timer? _reviewExpiryTimer;
  Timer? _reviewCheckTimer;
  bool _reviewExpired = false;
  String? _reviewIssue;
  bool _reviewVerified = false;
  bool _reviewLookupInFlight = false;
  NetworkMoveExecutionReview? _executionReview;
  NetworkMoveExecutionStatus? _executionStatus;
  String? _executionNotice;
  bool _executionBusy = false;
  bool _executionStatusVerified = false;
  bool _confirmationAttempted = false;
  int _reviewGeneration = 0;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    if (_executionApi != null) _restoreExecution();
  }

  NetworkMoveExecutionApi? get _executionApi =>
      widget.api is NetworkMoveExecutionApi &&
              (widget.api as NetworkMoveExecutionApi).executionAvailable
          ? widget.api as NetworkMoveExecutionApi
          : null;

  Future<void> _restoreExecution() async {
    final api = _executionApi;
    if (api == null) return;
    setState(() {
      _executionBusy = true;
      _executionStatusVerified = false;
    });
    try {
      final status = await api.currentExecution();
      if (mounted) {
        setState(() {
          _executionStatus = status;
          _executionStatusVerified = true;
          _executionNotice = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _executionNotice =
              'Execution status is unavailable. Check current status before taking any further action.',
        );
      }
    } finally {
      if (mounted) setState(() => _executionBusy = false);
    }
  }

  Future<void> _prepareExecution() async {
    final api = _executionApi;
    final plan = _plan;
    final generation = _reviewGeneration;
    if (api == null ||
        plan == null ||
        _executionBusy ||
        !_executionStatusVerified ||
        _executionStatus != null ||
        _confirmationAttempted ||
        !_reviewVerified ||
        _reviewExpired ||
        _reviewIssue != null ||
        !plan.readyForLabReview) {
      return;
    }
    setState(() {
      _executionBusy = true;
      _executionNotice = null;
      _executionReview = null;
      _confirmationAttempted = false;
    });
    try {
      final review = await api.prepareExecution(plan.reviewId);
      if (mounted &&
          generation == _reviewGeneration &&
          _plan?.reviewId == plan.reviewId &&
          !_reviewExpired &&
          _reviewIssue == null) {
        setState(() => _executionReview = review);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _executionNotice =
              'Execution could not be prepared. Check the isolated profile and evidence.',
        );
      }
    } finally {
      if (mounted) setState(() => _executionBusy = false);
    }
  }

  Future<void> _confirmExecution() async {
    final api = _executionApi;
    final review = _executionReview;
    if (api == null ||
        review == null ||
        _executionBusy ||
        !_executionStatusVerified ||
        _confirmationAttempted ||
        _reviewExpired ||
        _reviewIssue != null ||
        _plan?.reviewId != review.reviewId ||
        !review.expiresAt.isAfter(DateTime.now().toUtc())) {
      return;
    }
    // A lost reply may follow a native submission. Never offer a resend.
    setState(() {
      _executionBusy = true;
      _confirmationAttempted = true;
      _executionNotice = null;
    });
    try {
      final status = await api.confirmExecution(review.reviewId);
      if (mounted) {
        setState(() {
          _executionStatus = status;
          _executionReview = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _executionNotice =
              'The result is uncertain. Do not submit again. Check current status.',
        );
      }
    } finally {
      if (mounted) setState(() => _executionBusy = false);
    }
  }

  Future<void> _executionAction(String action, {bool resume = false}) async {
    final api = _executionApi;
    final status = _executionStatus;
    if (api == null || status == null || _executionBusy) return;
    setState(() {
      _executionBusy = true;
      _executionNotice = null;
    });
    try {
      final next = action == 'stop'
          ? await api.stopExecution(status.operationId)
          : await api.checkExecution(status.operationId, resume: resume);
      if (mounted) setState(() => _executionStatus = next);
    } catch (_) {
      if (mounted) {
        setState(
          () => _executionNotice =
              'Status could not be verified. Do not submit another move.',
        );
      }
    } finally {
      if (mounted) setState(() => _executionBusy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      if (_plan != null && !_reviewExpired && _reviewIssue == null) {
        setState(() {
          _reviewGeneration++;
          _reviewVerified = false;
        });
        _startReviewChecks();
        _checkReview();
      }
    } else {
      _reviewCheckTimer?.cancel();
      _reviewCheckTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reviewExpiryTimer?.cancel();
    _reviewCheckTimer?.cancel();
    super.dispose();
  }

  void _clearReview() {
    _reviewGeneration++;
    _reviewExpiryTimer?.cancel();
    _reviewExpiryTimer = null;
    _reviewCheckTimer?.cancel();
    _reviewCheckTimer = null;
    _plan = null;
    _reviewExpired = false;
    _reviewIssue = null;
    _reviewVerified = false;
    _executionReview = null;
  }

  void _invalidateDisplayedReview(String message) {
    _reviewGeneration++;
    _reviewExpiryTimer?.cancel();
    _reviewExpiryTimer = null;
    _reviewCheckTimer?.cancel();
    _reviewCheckTimer = null;
    _reviewVerified = false;
    _reviewIssue = message;
    _executionReview = null;
  }

  void _showPlan(NetworkMovePlan plan) {
    _reviewGeneration++;
    _reviewExpiryTimer?.cancel();
    _plan = plan;
    final remaining = plan.reviewValidUntil.difference(DateTime.now().toUtc());
    _reviewExpired = remaining <= Duration.zero;
    _reviewVerified = !_reviewExpired;
    if (!_reviewExpired) {
      _reviewExpiryTimer = Timer(remaining, () {
        if (mounted) {
          setState(() {
            _reviewExpired = true;
            _reviewVerified = false;
            _executionReview = null;
          });
          _reviewCheckTimer?.cancel();
          _reviewCheckTimer = null;
        }
      });
      _startReviewChecks();
    }
  }

  void _startReviewChecks() {
    if (_plan == null ||
        _reviewExpired ||
        _reviewIssue != null ||
        _lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _reviewCheckTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkReview(),
    );
  }

  Future<void> _checkReview() async {
    final plan = _plan;
    if (!mounted ||
        plan == null ||
        _reviewExpired ||
        _reviewIssue != null ||
        _lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true ||
        _reviewLookupInFlight) {
      return;
    }
    final generation = _reviewGeneration;
    _reviewLookupInFlight = true;
    try {
      final current = await widget.api.currentNetworkMovePlan().timeout(
            const Duration(seconds: 5),
          );
      if (!mounted || generation != _reviewGeneration) return;
      if (current == null ||
          current.reviewId != plan.reviewId ||
          !current.reviewValidUntil.isAfter(DateTime.now().toUtc())) {
        setState(() {
          _invalidateDisplayedReview(
            'This review is no longer current. Recheck the evidence and prepare a new review.',
          );
        });
      } else {
        setState(() => _reviewVerified = true);
      }
    } catch (_) {
      if (mounted && generation == _reviewGeneration) {
        setState(() {
          _invalidateDisplayedReview(
            'This review could not be verified. Recheck the evidence and prepare a new review.',
          );
        });
      }
    } finally {
      _reviewLookupInFlight = false;
      if (mounted &&
          generation != _reviewGeneration &&
          _plan != null &&
          !_reviewExpired &&
          _reviewIssue == null) {
        _checkReview();
      }
    }
  }

  Future<void> _update(Future<LiveState> Function() action) async {
    setState(() {
      _busy = true;
      _notice = null;
      _clearReview();
      _attested = false;
    });
    try {
      final next = await action().timeout(const Duration(seconds: 38));
      if (!mounted) return;
      setState(() {
        _state = next;
        if (!next.routers.any((router) => router.id == _targetRouterId)) {
          _targetRouterId = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'The local helper could not complete this check. Refresh discovery and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setUpAccess(String role) async {
    final next = await showDialog<LiveState>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CredentialSetupDialog(
        importDataset: (dataset) =>
            widget.api.credentialsForRole(role, dataset),
      ),
    );
    if (mounted && next != null) {
      setState(() {
        _state = next;
        _clearReview();
        _attested = false;
      });
    }
  }

  Future<void> _prepare() async {
    final target = _targetRouterId;
    if (_busy || !_attested || target == null) return;
    setState(() {
      _busy = true;
      _notice = null;
      _clearReview();
    });
    try {
      final plan = await widget.api
          .networkMovePlan(
            targetRouterId: target,
            attestation: EmptySourceAttestationInput(
              attestedAt: DateTime.now().toUtc(),
            ),
            delaySeconds: _delaySeconds,
          )
          .timeout(const Duration(seconds: 38));
      if (mounted) setState(() => _showPlan(plan));
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'The local helper could not prepare this review. Recheck the evidence and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readStatus(LiveProbe? probe) {
    if (probe == null) return 'Not checked';
    if (probe.identityMatch == 'mismatch') return 'Different network';
    if (probe.probeStatus == 'timeout') return 'Check timed out';
    if (probe.probeStatus == 'unsupported') return 'Check unavailable';
    if (probe.probeStatus == 'error') return 'Check failed';
    if (probe.probeStatus != 'completed' || !probe.verified) {
      return 'Check incomplete';
    }
    if (probe.pendingStatus == 'present') return 'Pending change present';
    return 'Authenticated read matches · pending empty';
  }

  String _blocker(String code) {
    const messages = <String, String>{
      'source_credentials_required': 'Set up source network access.',
      'target_credentials_required': 'Set up target network access.',
      'same_network': 'Source and target must be different networks.',
      'discovery_incomplete': 'Refresh router discovery.',
      'source_routers_unverified': 'No source routers have been identified.',
      'target_is_source':
          'The selected target also appears on the source network.',
      'empty_source_attestation_required':
          'Controlled empty-source evidence is required.',
      'empty_source_attestation_stale':
          'The controlled empty-source evidence has expired. Establish it again.',
      'invalid_delay': 'Choose a supported propagation delay.',
      'source_read_missing_or_stale':
          'Check every observed source router again.',
      'source_identity_unverified':
          'A source router did not match authenticated source access.',
      'source_pending_not_empty':
          'A source router has a pending change or unknown pending state.',
      'source_timestamp_unknown': 'A source active timestamp is unknown.',
      'source_timestamp_inconsistent':
          'Source router active timestamps differ.',
      'source_timestamp_mismatch':
          'A source router active timestamp changed after its check.',
      'target_read_missing_or_stale': 'Check the target router again.',
      'target_identity_unverified':
          'The target did not match authenticated target access.',
      'target_pending_not_empty':
          'The target has a pending change or unknown pending state.',
      'target_timestamp_unknown': 'The target active timestamp is unknown.',
      'target_timestamp_mismatch':
          'The target active timestamp changed after its check.',
      'source_advertisement_conflict':
          'A source advertisement conflicts with authenticated identity.',
    };
    return messages[code] ?? 'Additional evidence is required ($code).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final target =
        _state.routers.where((r) => r.id == _targetRouterId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Prepare a network move')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              children: [
                Text(
                  'Network move review',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  _executionApi == null
                      ? 'Read only · No network changes'
                      : 'Review first · Isolated lab execution available',
                ),
                const SizedBox(height: 12),
                Text(
                  _executionApi == null
                      ? 'A move would affect the entire source Thread network and all devices on it. This page only prepares a review; it cannot start a move.'
                      : 'A move affects the entire source Thread network and all devices on it. The isolated lab route requires a separate execution preparation and confirmation.',
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(key: Key('move-busy')),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _notice!,
                    key: const Key('move-error'),
                    style: TextStyle(color: colors.error),
                  ),
                ],
                const SizedBox(height: 20),
                Text('1. Network to keep', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text(
                  'Set up target access, choose its border router, then check it. An advertised name alone does not confirm the network.',
                ),
                const SizedBox(height: 8),
                Text(
                  _state.targetCredentialAvailable
                      ? 'Target access ready: ${_state.targetCredentialNetworkName ?? 'network name unavailable'}'
                      : 'Target access not set up',
                  key: const Key('move-target-access-status'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('move-target-access'),
                  onPressed: _busy ? null : () => _setUpAccess('target'),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Set up target access'),
                ),
                const SizedBox(height: 8),
                if (_state.routers.isEmpty)
                  const Text('Find routers before choosing a target.')
                else
                  for (final router in _state.routers)
                    ListTile(
                      key: Key('move-target-${router.id}'),
                      minLeadingWidth: 24,
                      leading: Icon(
                        _targetRouterId == router.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(
                        router.serviceName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Advertised: ${router.networkName ?? 'unknown'} · ${_readStatus(router.roleProbes['target'])}',
                      ),
                      selected: _targetRouterId == router.id,
                      onTap: _busy
                          ? null
                          : () => setState(() {
                                _targetRouterId = router.id;
                                _clearReview();
                                _attested = false;
                              }),
                    ),
                if (target != null)
                  OutlinedButton(
                    key: const Key('move-check-target'),
                    onPressed: _busy ||
                            !_state.targetCredentialAvailable ||
                            !target.endpointUsable
                        ? null
                        : () => _update(
                              () =>
                                  widget.api.probeForRole('target', target.id),
                            ),
                    child: const Text('Check target router'),
                  ),
                const SizedBox(height: 18),
                Text('2. Source network', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text(
                  'Set up separate source access. Check each observed router that may belong to the source network. The planner will list every observed source router together.',
                ),
                const SizedBox(height: 8),
                Text(
                  _state.sourceCredentialAvailable
                      ? 'Source access ready: ${_state.sourceCredentialNetworkName ?? 'network name unavailable'}'
                      : 'Source access not set up',
                  key: const Key('move-source-access-status'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('move-source-access'),
                  onPressed: _busy ? null : () => _setUpAccess('source'),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Set up source access'),
                ),
                const SizedBox(height: 8),
                for (final router in _state.routers.where(
                  (r) => r.id != _targetRouterId,
                ))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            router.serviceName,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            'Source check: ${_readStatus(router.roleProbes['source'])}',
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton(
                            key: Key('move-check-source-${router.id}'),
                            onPressed: _busy ||
                                    !_state.sourceCredentialAvailable ||
                                    !router.endpointUsable
                                ? null
                                : () => _update(
                                      () => widget.api.probeForRole(
                                        'source',
                                        router.id,
                                      ),
                                    ),
                            child: const Text('Check as source'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('move-discover'),
                  onPressed: _busy || _state.discoveryStatus == 'unsupported'
                      ? null
                      : () => _update(widget.api.discover),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh router discovery'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Offline or unobserved devices remain unknown. Discovery is not a complete inventory.',
                ),
                const SizedBox(height: 20),
                Text(
                  '3. Controlled empty-source evidence',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'The first supported case requires an operator-controlled inventory showing that the whole source network is empty. Missing advertisements or an empty child table do not establish this.',
                ),
                CheckboxListTile(
                  key: const Key('move-empty-source-attestation'),
                  contentPadding: EdgeInsets.zero,
                  value: _attested,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _attested = value ?? false;
                            _clearReview();
                          }),
                  title: const Text(
                    'I established a controlled inventory and confirm the whole source network has no attached devices.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 12),
                Text('4. Prepare review', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text(
                  'Choose the proposed propagation delay. Preparation checks evidence only and does not send a network command.',
                ),
                DropdownButtonFormField<int>(
                  key: const Key('move-delay'),
                  initialValue: _delaySeconds,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Propagation delay',
                  ),
                  items: const [
                    DropdownMenuItem(value: 300, child: Text('5 minutes')),
                    DropdownMenuItem(value: 900, child: Text('15 minutes')),
                    DropdownMenuItem(value: 1800, child: Text('30 minutes')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _delaySeconds = value ?? 300;
                            _clearReview();
                            _attested = false;
                          }),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('move-prepare'),
                  onPressed: _busy || !_attested || _targetRouterId == null
                      ? null
                      : _prepare,
                  child: const Text('Prepare read-only review'),
                ),
                if (_plan != null) _review(_plan!),
                const SizedBox(height: 16),
                if (_executionApi == null)
                  OutlinedButton.icon(
                    key: const Key('move-dispatch-disabled'),
                    onPressed: null,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Start network move · unavailable'),
                  )
                else
                  _executionSection(),
                const SizedBox(height: 8),
                const Text(
                  'The actual adapter and device/firmware route need separate lab and vendor verification. No rollback is guaranteed.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _review(NetworkMovePlan plan) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('move-review'),
      margin: const EdgeInsets.only(top: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Source network review', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              _reviewExpired
                  ? 'This review has expired. Recheck the evidence and prepare a new review.'
                  : _reviewIssue != null
                      ? _reviewIssue!
                      : !_reviewVerified
                          ? 'Checking whether this review is still current.'
                          : plan.readyForLabReview
                              ? 'Evidence ready for separate lab review.'
                              : 'More evidence is needed.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Affected scope: the entire source Thread network and all devices on it.',
            ),
            const Text(
              'Offline or unobserved devices remain unknown. This is not a complete inventory.',
            ),
            const SizedBox(height: 10),
            Text(
              'Observed source routers (${plan.sourceRouters.length})',
              style: theme.textTheme.titleMedium,
            ),
            if (plan.sourceRouters.isEmpty)
              const Text('No source routers identified by the planner.'),
            for (final router in plan.sourceRouters)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(router.serviceName),
                subtitle: Text(
                  'Read: ${router.readStatus.replaceAll('_', ' ')}',
                ),
              ),
            if (plan.blockers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Evidence still needed', style: theme.textTheme.titleMedium),
              for (final blocker in plan.blockers)
                Text('• ${_blocker(blocker)}'),
            ],
            const SizedBox(height: 10),
            Text(
              plan.delaySeconds % 60 == 0
                  ? 'Propagation delay: ${plan.delaySeconds ~/ 60} minutes'
                  : 'Propagation delay: ${plan.delaySeconds} seconds',
            ),
            const Text(
              'A move could interrupt the source network during propagation.',
            ),
            Text(
              'Verification schedule: after the proposed propagation delay, ${plan.verification}',
            ),
            Text('Recovery: ${plan.recovery}'),
            const Text(
              'Manual recovery may be required. Rollback is not guaranteed.',
            ),
            Text('Review expires: ${plan.reviewValidUntil.toLocal()}'),
          ],
        ),
      ),
    );
  }

  Widget _executionSection() {
    final review = _executionReview;
    final status = _executionStatus;
    final plan = _plan;
    return Card(
      key: const Key('move-execution-section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Isolated lab execution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Available only for the trusted OpenThread POSIX lab profile.',
            ),
            if (_executionBusy)
              const LinearProgressIndicator(key: Key('move-execution-busy')),
            if (_executionNotice != null)
              Text(_executionNotice!, key: const Key('move-execution-notice')),
            if (status == null && review == null) ...[
              FilledButton(
                key: const Key('move-execution-prepare'),
                onPressed: _executionBusy ||
                        !_executionStatusVerified ||
                        _confirmationAttempted ||
                        plan == null ||
                        !plan.readyForLabReview ||
                        !_reviewVerified ||
                        _reviewExpired ||
                        _reviewIssue != null
                    ? null
                    : _prepareExecution,
                child: const Text('Prepare actual execution'),
              ),
              OutlinedButton(
                key: const Key('move-execution-current'),
                onPressed: _executionBusy ? null : _restoreExecution,
                child: const Text('Check current status'),
              ),
            ],
            if (review != null && status == null) ...[
              Text('Operation: ${review.operationId}'),
              Text('Profile: ${review.profileId}'),
              const Text(
                'Scope: the whole source Thread network, including offline or unobserved devices.',
              ),
              Text(
                'Observed source routers: ${review.sourceRouterIds.join(', ')}',
              ),
              Text('Target router: ${review.targetRouterId}'),
              Text(
                'Propagation delay: ${review.delaySeconds} seconds; observation: ${review.observationSeconds} seconds.',
              ),
              const Text(
                'The isolated source must have no attached devices. The move may interrupt it. Manual recovery may be required; rollback is not guaranteed.',
              ),
              Text('Confirmation expires: ${review.expiresAt.toLocal()}'),
              FilledButton(
                key: const Key('move-execution-confirm'),
                onPressed: _executionBusy ||
                        _confirmationAttempted ||
                        _reviewExpired ||
                        _reviewIssue != null ||
                        _plan?.reviewId != review.reviewId ||
                        !review.expiresAt.isAfter(DateTime.now().toUtc())
                    ? null
                    : _confirmExecution,
                child: const Text('Confirm and start this operation once'),
              ),
              if (_confirmationAttempted)
                OutlinedButton(
                  key: const Key('move-execution-current'),
                  onPressed: _executionBusy ? null : _restoreExecution,
                  child: const Text('Check current status'),
                ),
            ],
            if (status != null) ...[
              Text(
                'Operation: ${status.operationId}',
                key: const Key('move-execution-operation'),
              ),
              Text(
                'Stage: ${status.stage.replaceAll('_', ' ')}',
                key: const Key('move-execution-stage'),
              ),
              Text('Disposition: ${status.disposition.replaceAll('_', ' ')}'),
              Text('Reason: ${status.reason.replaceAll('_', ' ')}'),
              const Text(
                'Command acceptance is separate from observed network convergence. Do not submit another move while the outcome is unresolved.',
              ),
              OutlinedButton(
                key: const Key('move-execution-check'),
                onPressed:
                    _executionBusy ? null : () => _executionAction('check'),
                child: const Text('Check outcome'),
              ),
              if (status.stage == 'observation_stopped')
                OutlinedButton(
                  key: const Key('move-execution-resume'),
                  onPressed: _executionBusy
                      ? null
                      : () => _executionAction('check', resume: true),
                  child: const Text('Resume observation'),
                ),
              if (!status.terminal && status.stage != 'observation_stopped')
                OutlinedButton(
                  key: const Key('move-execution-stop'),
                  onPressed:
                      _executionBusy ? null : () => _executionAction('stop'),
                  child: const Text('Stop observation'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
