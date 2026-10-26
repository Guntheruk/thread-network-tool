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
    this.now,
  });

  final NetworkMoveApi api;
  final LiveState initialState;
  final DateTime Function()? now;

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
  bool _eeroConfirmed = false;
  bool _groupConfirmed = false;
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
  Timer? _automaticCheckTimer;
  int _automaticCheckGeneration = 0;
  int _automaticCheckAttempts = 0;
  bool _automaticChecksActive = false;
  bool _automaticChecksStarted = false;
  bool _automaticChecksPaused = false;
  DateTime? _automaticObserveAfter;
  DateTime? _automaticDeadline;
  String? _automaticOperationId;
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
              (widget.api as NetworkMoveExecutionApi).executionRecoveryAvailable
          ? widget.api as NetworkMoveExecutionApi
          : null;

  bool get _macExecution =>
      widget.api is ExecutionProfileInfo &&
      (widget.api as ExecutionProfileInfo).executionProfileId ==
          'eero-source-network-alpha-v1';

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  void _cancelAutomaticChecks({bool paused = false}) {
    _automaticCheckGeneration++;
    _automaticCheckTimer?.cancel();
    _automaticCheckTimer = null;
    _automaticChecksActive = false;
    _automaticChecksPaused = paused;
  }

  void _startAutomaticChecks(NetworkMoveExecutionStatus status) {
    _cancelAutomaticChecks();
    if (!_macExecution ||
        status.profileId != 'eero-source-network-alpha-v1' ||
        status.terminal ||
        status.stage == 'observation_stopped' ||
        !{'accepted', 'uncertain', 'rejected'}.contains(status.disposition) ||
        status.observeAfter == null ||
        status.observationSeconds == null ||
        _lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final observeAfter = status.observeAfter!;
    final deadline = observeAfter.add(const Duration(minutes: 2));
    if (_now.isAfter(deadline) ||
        observeAfter.isAfter(_now.add(const Duration(minutes: 10)))) {
      _automaticChecksPaused = true;
      return;
    }
    _automaticChecksActive = true;
    _automaticChecksStarted = false;
    _automaticCheckAttempts = 0;
    _automaticObserveAfter = observeAfter;
    _automaticDeadline = deadline;
    _automaticOperationId = status.operationId;
    _scheduleAutomaticCheck();
  }

  void _scheduleAutomaticCheck() {
    if (!_automaticChecksActive ||
        _lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (_automaticCheckAttempts >= 13 || _now.isAfter(_automaticDeadline!)) {
      setState(() => _cancelAutomaticChecks(paused: true));
      return;
    }
    final delay = _automaticChecksStarted
        ? const Duration(seconds: 10)
        : _automaticObserveAfter!.difference(_now);
    final generation = _automaticCheckGeneration;
    _automaticCheckTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => _runAutomaticCheck(generation),
    );
  }

  Future<void> _runAutomaticCheck(int generation) async {
    if (!mounted ||
        !_automaticChecksActive ||
        generation != _automaticCheckGeneration ||
        _lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (_now.isAfter(_automaticDeadline!)) {
      setState(() => _cancelAutomaticChecks(paused: true));
      return;
    }
    if (_executionBusy) {
      _automaticCheckTimer = Timer(
          const Duration(seconds: 1), () => _runAutomaticCheck(generation));
      return;
    }
    final api = _executionApi;
    final operationId = _automaticOperationId;
    if (api == null || operationId == null) {
      setState(() => _cancelAutomaticChecks(paused: true));
      return;
    }
    setState(() {
      _automaticChecksStarted = true;
      _automaticCheckAttempts++;
      _executionBusy = true;
    });
    try {
      final next = await api
          .checkExecution(operationId)
          .timeout(const Duration(seconds: 130));
      if (!mounted || generation != _automaticCheckGeneration) return;
      if (next.operationId != operationId ||
          next.profileId != 'eero-source-network-alpha-v1') {
        setState(() => _cancelAutomaticChecks(paused: true));
        return;
      }
      setState(() {
        _executionStatus = next;
        _executionNotice = null;
        if (next.terminal || next.stage == 'observation_stopped') {
          _cancelAutomaticChecks();
        }
      });
    } on TimeoutException {
      if (mounted && generation == _automaticCheckGeneration) {
        setState(() => _cancelAutomaticChecks(paused: true));
      }
    } catch (_) {
      // A completed failed read may be checked again inside the bounded window.
      if (mounted &&
          generation == _automaticCheckGeneration &&
          _now.isAfter(_automaticDeadline!)) {
        setState(() => _cancelAutomaticChecks(paused: true));
      }
    } finally {
      if (mounted && generation == _automaticCheckGeneration) {
        setState(() => _executionBusy = false);
        if (_automaticChecksActive) _scheduleAutomaticCheck();
      } else if (mounted) {
        setState(() => _executionBusy = false);
      }
    }
  }

  Future<void> _restoreExecution() async {
    final api = _executionApi;
    if (api == null) return;
    setState(() {
      _cancelAutomaticChecks();
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
        !api.executionAvailable ||
        plan == null ||
        _executionBusy ||
        !_executionStatusVerified ||
        _executionStatus != null ||
        _confirmationAttempted ||
        !_reviewVerified ||
        _reviewExpired ||
        _reviewIssue != null ||
        !plan.readyForExecutionReview) {
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
          () => _executionNotice = _macExecution
              ? 'The join could not be prepared. Check the routers and try the review again.'
              : 'Execution could not be prepared. Check the isolated profile and evidence.',
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
          if (_macExecution) {
            _clearReview();
          } else {
            _executionReview = null;
          }
          _executionStatus = status;
          _startAutomaticChecks(status);
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
      _cancelAutomaticChecks();
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
      if (_automaticChecksActive) {
        setState(() => _cancelAutomaticChecks(paused: true));
      }
      _reviewCheckTimer?.cancel();
      _reviewCheckTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reviewExpiryTimer?.cancel();
    _reviewCheckTimer?.cancel();
    _cancelAutomaticChecks();
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
      _eeroConfirmed = false;
      _groupConfirmed = false;
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
        _eeroConfirmed = false;
        _groupConfirmed = false;
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
              operatorEeroSource: _macExecution && _eeroConfirmed,
              allSourceEerosRepresented: _macExecution && _groupConfirmed,
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
    if (probe.pendingStatus == 'present') {
      return _macExecution
          ? 'Another change is already scheduled'
          : 'Pending change present';
    }
    return _macExecution
        ? 'Settings match'
        : 'Authenticated read matches · pending empty';
  }

  String _blocker(String code) {
    const messages = <String, String>{
      'source_credentials_required': 'Set up access to Network to move.',
      'target_credentials_required': 'Set up access to Network to keep.',
      'same_network': 'Network to move and Network to keep must be different.',
      'discovery_incomplete': 'Refresh router discovery.',
      'source_routers_unverified':
          'No border routers to move have been identified.',
      'target_is_source':
          'The selected router also appears on Network to move.',
      'empty_source_attestation_required':
          'Confirm that Network to move has no attached devices.',
      'empty_source_attestation_stale':
          'The empty-network evidence has expired. Establish it again.',
      'invalid_delay': 'Choose a supported propagation delay.',
      'source_read_missing_or_stale':
          'Check every observed border router being moved again.',
      'source_identity_unverified':
          'A router being moved did not match access to Network to move.',
      'source_pending_not_empty':
          'A router being moved has a pending change or unknown pending state.',
      'source_timestamp_unknown':
          'A router being moved has an unknown active timestamp.',
      'source_timestamp_inconsistent':
          'Active timestamps differ among routers being moved.',
      'source_timestamp_mismatch':
          'A router being moved changed its active timestamp after the check.',
      'target_read_missing_or_stale':
          'Check the router on Network to keep again.',
      'target_identity_unverified':
          'The router did not match access to Network to keep.',
      'target_pending_not_empty':
          'The router on Network to keep has a pending change or unknown pending state.',
      'target_timestamp_unknown':
          'The router on Network to keep has an unknown active timestamp.',
      'target_timestamp_mismatch':
          'The router on Network to keep changed its active timestamp after the check.',
      'source_advertisement_conflict':
          'An advertisement for a router being moved conflicts with its authenticated identity.',
      'operator_eero_source_required':
          'Confirm that Network to move is the eero Thread network in the eero app.',
      'source_group_attestation_required':
          'Confirm that every source eero border router is represented in this review.',
      'pinned_endpoint_unavailable':
          'A reviewed router has no supported pinned local endpoint.',
    };
    return messages[code] ?? 'Additional evidence is required ($code).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canExecute = _executionApi?.executionAvailable ?? false;
    final target =
        _state.routers.where((r) => r.id == _targetRouterId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _macExecution ? 'Join Eero network' : 'Prepare a network move'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              children: [
                Text(
                  _macExecution ? 'Join Eero network' : 'Network move review',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  _executionApi == null
                      ? 'Read only · No network changes'
                      : canExecute
                          ? _macExecution
                              ? 'Review before joining'
                              : 'Review first · Isolated lab execution available'
                          : 'Saved operation recovery · Execution unavailable',
                ),
                const SizedBox(height: 12),
                Text(
                  _executionApi == null
                      ? 'A move would change the border routers on Network to move so they join Network to keep. Other devices may lose connectivity. Accessories need a separate supported move. This page only prepares a review.'
                      : _macExecution
                          ? 'This moves every Eero on ${_state.sourceCredentialNetworkName ?? 'Network to move'} to ${_state.targetCredentialNetworkName ?? 'Network to keep'}. Only continue if the source network has no accessories. The network you keep stays unchanged.'
                          : 'A move changes the border routers on Network to move so they join Network to keep. Other devices may lose connectivity; accessories need a separate supported move. The isolated lab route requires separate preparation and confirmation.',
                ),
                if (_executionApi != null &&
                    (_executionStatus != null ||
                        !_executionStatusVerified)) ...[
                  const SizedBox(height: 12),
                  _executionSection(),
                ],
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
                Text(
                    _macExecution ? '1. Network to join' : '1. Network to keep',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(_macExecution
                    ? 'Choose the network your Eeros will join, then check its settings.'
                    : 'Set up access to the network you want to keep, choose its border router, then check it. An advertised name alone does not confirm the network.'),
                const SizedBox(height: 8),
                Text(
                  _state.targetCredentialAvailable
                      ? 'Network to keep access ready: ${_state.targetCredentialNetworkName ?? 'network name unavailable'}'
                      : 'Network to keep access not set up',
                  key: const Key('move-target-access-status'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('move-target-access'),
                  onPressed: _busy ? null : () => _setUpAccess('target'),
                  icon: const Icon(Icons.key_outlined),
                  label: Text(_macExecution
                      ? 'Set up network to join'
                      : 'Set up Network to keep access'),
                ),
                const SizedBox(height: 8),
                if (_state.routers.isEmpty)
                  const Text(
                      'Find routers before choosing one on Network to keep.')
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
                    child: Text(_macExecution
                        ? 'Check network to join'
                        : 'Check router on Network to keep'),
                  ),
                const SizedBox(height: 18),
                Text(
                    _macExecution
                        ? '2. Eero network to move'
                        : '2. Network to move',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(_macExecution
                    ? 'Check each Eero on the network you are moving.'
                    : 'Set up access to the network whose border routers you want to move. Check each observed router that may belong to it. The review lists those routers together.'),
                const SizedBox(height: 8),
                Text(
                  _state.sourceCredentialAvailable
                      ? 'Network to move access ready: ${_state.sourceCredentialNetworkName ?? 'network name unavailable'}'
                      : 'Network to move access not set up',
                  key: const Key('move-source-access-status'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('move-source-access'),
                  onPressed: _busy ? null : () => _setUpAccess('source'),
                  icon: const Icon(Icons.key_outlined),
                  label: Text(_macExecution
                      ? 'Set up Eero network'
                      : 'Set up Network to move access'),
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
                            'Network to move check: ${_readStatus(router.roleProbes['source'])}',
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
                            child: Text(_macExecution
                                ? 'Check Eero'
                                : 'Check for Network to move'),
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
                  label: Text(_macExecution
                      ? 'Find routers again'
                      : 'Refresh router discovery'),
                ),
                if (!_macExecution) ...[
                  const SizedBox(height: 10),
                  const Text(
                      'Offline or unobserved devices remain unknown. Discovery is not a complete inventory.'),
                ],
                const SizedBox(height: 20),
                Text(
                  _macExecution
                      ? '3. Confirm the Eero network is empty'
                      : '3. Confirm Network to move is empty',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(_macExecution
                    ? 'Check your home setup to make sure the Eero network you are moving has no accessories.'
                    : 'This first supported case requires a controlled inventory showing no attached devices on Network to move. Its border routers remain present. Missing advertisements or an empty child table do not prove this.'),
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
                  title: Text(_macExecution
                      ? 'I checked every device and confirm this Eero network has no accessories.'
                      : 'I established a controlled inventory and confirm Network to move has no attached devices.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (_macExecution) ...[
                  CheckboxListTile(
                    key: const Key('move-eero-source-attestation'),
                    contentPadding: EdgeInsets.zero,
                    value: _eeroConfirmed,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                              _eeroConfirmed = value ?? false;
                              _clearReview();
                            }),
                    title: const Text(
                        'I checked in eero that this is my Eero network.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    key: const Key('move-whole-eero-group-attestation'),
                    contentPadding: EdgeInsets.zero,
                    value: _groupConfirmed,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                              _groupConfirmed = value ?? false;
                              _clearReview();
                            }),
                    title: const Text(
                        'I checked that every Eero on this network is listed.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const ExpansionTile(
                    title: Text('Details'),
                    children: [
                      Text(
                          'Router advertisements do not prove the manufacturer or reveal offline devices. If a router endpoint changes, the app requires manual review and will not resend the command.'),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(_macExecution ? '4. Review join' : '4. Prepare review',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(_macExecution
                    ? 'This review checks settings only. After joining, allow at least 5 minutes for settings to update.'
                    : 'Choose the proposed propagation delay. Preparation checks evidence only and does not send a network command.'),
                if (!_macExecution)
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
                  onPressed: _busy ||
                          !_attested ||
                          (_macExecution &&
                              (!_eeroConfirmed || !_groupConfirmed)) ||
                          _targetRouterId == null
                      ? null
                      : _prepare,
                  child: Text(_macExecution
                      ? 'Review join'
                      : 'Prepare read-only review'),
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
                else if (_executionStatus == null && _executionStatusVerified)
                  _executionSection(),
                const SizedBox(height: 8),
                if (!_macExecution)
                  const Text(
                      'The actual adapter and device/firmware route need separate lab and vendor verification. No rollback is guaranteed.'),
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
            Text(_macExecution ? 'Review join' : 'Network to move review',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              _reviewExpired
                  ? 'This review has expired. Recheck the evidence and prepare a new review.'
                  : _reviewIssue != null
                      ? _reviewIssue!
                      : !_reviewVerified
                          ? 'Checking whether this review is still current.'
                          : plan.readyForExecutionReview
                              ? _macExecution
                                  ? 'Settings checked. Review the join before continuing.'
                                  : 'Evidence ready for separate lab review.'
                              : 'More evidence is needed.',
            ),
            const SizedBox(height: 8),
            if (!_macExecution) ...[
              const Text(
                  'Proposed change: move the border routers on Network to move to Network to keep. Other devices may lose connectivity; accessories are not moved by this action.'),
              const Text(
                  'Offline or unobserved devices remain unknown. This is not a complete inventory.'),
            ],
            const SizedBox(height: 10),
            Text(
              _macExecution
                  ? 'Eeros to move (${plan.sourceRouters.length})'
                  : 'Observed border routers to move (${plan.sourceRouters.length})',
              style: theme.textTheme.titleMedium,
            ),
            if (plan.sourceRouters.isEmpty)
              const Text('No border routers to move identified by the review.'),
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
            if (!_macExecution) ...[
              const Text(
                  'A move could interrupt Network to move during propagation.'),
              const Text(
                  'After the propagation delay, recheck the routers being moved and the network being kept.'),
              Text('Recovery: ${plan.recovery}'),
              const Text(
                  'Manual recovery may be required. Rollback is not guaranteed.'),
            ],
            if (_macExecution)
              const ExpansionTile(
                title: Text('Details'),
                children: [
                  Text(
                      'Offline devices remain unknown. The join can interrupt the source network. Manual recovery may be required; rollback is not guaranteed.'),
                ],
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
              _macExecution ? 'Join network' : 'Isolated lab execution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (!_macExecution)
              const Text(
                  'Available only for the trusted OpenThread POSIX lab profile.'),
            if (_executionBusy)
              const LinearProgressIndicator(key: Key('move-execution-busy')),
            if (_executionNotice != null)
              Text(_executionNotice!, key: const Key('move-execution-notice')),
            if (status == null && review == null) ...[
              FilledButton(
                key: const Key('move-execution-prepare'),
                onPressed: !_executionApi!.executionAvailable ||
                        _executionBusy ||
                        !_executionStatusVerified ||
                        _confirmationAttempted ||
                        plan == null ||
                        !plan.readyForExecutionReview ||
                        !_reviewVerified ||
                        _reviewExpired ||
                        _reviewIssue != null
                    ? null
                    : _prepareExecution,
                child: Text(
                    _macExecution ? 'Check join' : 'Prepare actual execution'),
              ),
              OutlinedButton(
                key: const Key('move-execution-current'),
                onPressed: _executionBusy ? null : _restoreExecution,
                child: const Text('Check current status'),
              ),
            ],
            if (review != null && status == null) ...[
              if (_macExecution) ...[
                Text('Eeros selected: ${review.sourceRouterIds.length}'),
                Text(
                    'Join: ${_state.targetCredentialNetworkName ?? 'Network to keep'}'),
                const Text(
                    'The checked settings are ready. This action starts the join once.'),
                ExpansionTile(
                  title: const Text('Details'),
                  children: [
                    Text('Operation: ${review.operationId}'),
                    Text('Profile: ${review.profileId}'),
                    Text(
                        'Source router IDs: ${review.sourceRouterIds.join(', ')}'),
                    Text('Target router ID: ${review.targetRouterId}'),
                    Text(
                        'Delay: ${review.delaySeconds} seconds; observation: ${review.observationSeconds} seconds.'),
                  ],
                ),
              ] else ...[
                Text('Operation: ${review.operationId}'),
                Text('Profile: ${review.profileId}'),
                const Text(
                    'Scope: border routers on Network to move. Offline or unobserved devices may be affected; this does not move accessories.'),
                Text(
                    'Observed border routers to move: ${review.sourceRouterIds.join(', ')}'),
                Text('Router on Network to keep: ${review.targetRouterId}'),
                Text(
                    'Propagation delay: ${review.delaySeconds} seconds; observation: ${review.observationSeconds} seconds.'),
                const Text(
                    'Network to move must have no attached devices in this isolated lab profile. The move may interrupt it. Manual recovery may be required; rollback is not guaranteed.'),
              ],
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
                child: Text(_macExecution
                    ? 'Join network'
                    : 'Confirm and start this operation once'),
              ),
              if (_confirmationAttempted)
                OutlinedButton(
                  key: const Key('move-execution-current'),
                  onPressed: _executionBusy ? null : _restoreExecution,
                  child: const Text('Check current status'),
                ),
            ],
            if (status != null) ...[
              if (_macExecution) ...[
                if (_automaticChecksActive)
                  Text(
                    _automaticChecksStarted
                        ? 'Checking routers'
                        : 'Settings are applying. Checks start in about 5 minutes.',
                    key: const Key('move-automatic-progress'),
                  ),
                if (_automaticChecksPaused && !status.terminal)
                  const Text(
                    'Automatic checks are paused. Use Check settings to continue manually.',
                    key: Key('move-automatic-paused'),
                  ),
                Text(
                  switch (status.stage) {
                    'verified_configuration' => 'Network settings verified',
                    'verified_unchanged' => 'Network settings unchanged',
                    'proven_not_sent' => 'Join was not sent',
                    'needs_attention' => 'Join needs attention',
                    'observation_stopped' => 'Settings checks stopped',
                    _ => 'Checking network settings',
                  },
                  key: const Key('move-execution-stage'),
                ),
                Text(switch (status.stage) {
                  'verified_configuration' =>
                    'All selected routers report the chosen settings. Accessory connectivity has not been tested.',
                  'verified_unchanged' =>
                    'The change was rejected and fresh checks confirm the original network settings.',
                  'proven_not_sent' =>
                    'No network change was sent. You can review the setup before trying a new join.',
                  _ =>
                    'Do not start another join while this outcome is unresolved.',
                }),
                ExpansionTile(
                  title: const Text('Details'),
                  children: [
                    Text('Operation: ${status.operationId}',
                        key: const Key('move-execution-operation')),
                    Text('Stage: ${status.stage}'),
                    Text('Disposition: ${status.disposition}'),
                    Text('Reason: ${status.reason}'),
                  ],
                ),
              ] else ...[
                Text('Operation: ${status.operationId}',
                    key: const Key('move-execution-operation')),
                Text('Stage: ${status.stage.replaceAll('_', ' ')}',
                    key: const Key('move-execution-stage')),
                Text('Disposition: ${status.disposition.replaceAll('_', ' ')}'),
                Text('Reason: ${status.reason.replaceAll('_', ' ')}'),
                const Text(
                    'Command acceptance is separate from observed network convergence. Do not submit another move while the outcome is unresolved.'),
              ],
              OutlinedButton(
                key: const Key('move-execution-check'),
                onPressed:
                    _executionBusy ? null : () => _executionAction('check'),
                child: Text(_macExecution ? 'Check settings' : 'Check outcome'),
              ),
              if (status.stage == 'observation_stopped')
                OutlinedButton(
                  key: const Key('move-execution-resume'),
                  onPressed: _executionBusy
                      ? null
                      : () => _executionAction('check', resume: true),
                  child: Text(
                      _macExecution ? 'Resume checks' : 'Resume observation'),
                ),
              if (status.terminal)
                OutlinedButton(
                  key: const Key('move-new-review'),
                  onPressed: _executionBusy
                      ? null
                      : () => setState(() {
                            // Keep the durable terminal journal. A future operation
                            // needs a new review, attestations and confirmation.
                            _clearReview();
                            _executionStatus = null;
                            _executionNotice = null;
                            _confirmationAttempted = false;
                            _attested = false;
                            _eeroConfirmed = false;
                            _groupConfirmed = false;
                          }),
                  child: const Text('Review another join'),
                ),
              if (!status.terminal && status.stage != 'observation_stopped')
                OutlinedButton(
                  key: const Key('move-execution-stop'),
                  onPressed:
                      _executionBusy ? null : () => _executionAction('stop'),
                  child:
                      Text(_macExecution ? 'Stop checks' : 'Stop observation'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
