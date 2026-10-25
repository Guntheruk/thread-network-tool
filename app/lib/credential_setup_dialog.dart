import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'apple_credentials.dart';
import 'live_api.dart';

/// Guided, read-only credential import. The API validates the complete dataset;
/// this dialog only rejects obviously malformed input before sending it.
class CredentialSetupDialog extends StatefulWidget {
  const CredentialSetupDialog({
    super.key,
    required this.importDataset,
    this.appleCredentials,
    this.showAppleRoute,
  });

  final Future<LiveState> Function(String dataset) importDataset;
  final AppleCredentials? appleCredentials;
  final bool? showAppleRoute;

  @override
  State<CredentialSetupDialog> createState() => _CredentialSetupDialogState();
}

enum _Route { choose, apple, eero, advanced }

class _CredentialSetupDialogState extends State<CredentialSetupDialog> {
  final TextEditingController _controller = TextEditingController();
  late final AppleCredentials _appleCredentials =
      widget.appleCredentials ?? AppleCredentials();
  _Route _route = _Route.choose;
  bool _importing = false;
  bool _checkingApple = false;
  bool _fetchingApple = false;
  bool _closing = false;
  bool _failed = false;
  AppleCredentialStatus? _appleStatus;

  bool get _showAppleRoute =>
      widget.showAppleRoute ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.iOS));

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _choose(_Route route) {
    _controller.clear();
    setState(() {
      _route = route;
      _failed = false;
      _appleStatus = null;
    });
  }

  bool _validDataset(String dataset) =>
      dataset.length <= 508 &&
      RegExp(r'^(?:[0-9a-fA-F]{2})+$').hasMatch(dataset);

  Future<void> _importDataset(String dataset) async {
    if (!_validDataset(dataset)) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _importing = true;
      _failed = false;
    });
    try {
      final state = await widget
          .importDataset(dataset)
          .timeout(const Duration(seconds: 38));
      if (mounted) Navigator.of(context).pop(state);
    } catch (_) {
      if (mounted) {
        setState(() {
          _importing = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _submit() async {
    final dataset = _controller.text.trim();
    _controller.clear();
    await _importDataset(dataset);
  }

  Future<void> _chooseApple() async {
    _choose(_Route.apple);
    setState(() => _checkingApple = true);
    AppleCredentialResult result;
    try {
      result = await _appleCredentials.availability();
    } catch (_) {
      result = const AppleCredentialResult(AppleCredentialStatus.failure);
    }
    if (!mounted || _closing || _route != _Route.apple) return;
    setState(() {
      _checkingApple = false;
      _appleStatus = result.status;
    });
  }

  Future<void> _fetchApple() async {
    setState(() {
      _fetchingApple = true;
      _failed = false;
    });
    AppleCredentialResult result;
    try {
      result = await _appleCredentials.fetchPreferred();
    } catch (_) {
      result = const AppleCredentialResult(AppleCredentialStatus.failure);
    }
    if (!mounted || _closing || _route != _Route.apple) return;
    setState(() {
      _fetchingApple = false;
      _appleStatus = result.status;
    });
    if (result.status == AppleCredentialStatus.available) {
      final dataset = result.datasetHex;
      if (dataset == null || !_validDataset(dataset)) {
        setState(() => _failed = true);
        return;
      }
      await _importDataset(dataset);
    }
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    if (_fetchingApple) await _appleCredentials.cancelFetch();
    if (mounted) Navigator.of(context).pop();
  }

  String _appleStatusMessage(AppleCredentialStatus? status) {
    switch (status) {
      case AppleCredentialStatus.available:
        return 'Apple may ask your permission to use saved Thread credentials. After setup, choose a router and tap Check to confirm it matches. The device’s preferred network may differ from the router’s advertised network.';
      case AppleCredentialStatus.noCredentials:
        return 'No saved Thread network credentials were found on this device. Use eero or Advanced to set up access: copy the Active operational dataset from the eero app, or enter a complete dataset you already have.';
      case AppleCredentialStatus.permissionDenied:
        return 'Access to saved credentials was declined. You can use eero or Advanced to set up access.';
      case AppleCredentialStatus.accessNotConfigured:
        return 'Apple credential access is unavailable in this build. Use eero or Advanced to set up access.';
      case AppleCredentialStatus.unavailable:
        return 'Saved Apple credentials are unavailable on this device. Use eero or Advanced to set up access.';
      case AppleCredentialStatus.failure:
        return 'Saved credentials could not be checked. Try again or use eero or Advanced.';
      case AppleCredentialStatus.timedOut:
        return 'Apple did not respond in time. Try again or use eero or Advanced.';
      case AppleCredentialStatus.cancelled:
        return 'The request was cancelled. Use eero or Advanced, or try Apple again.';
      case AppleCredentialStatus.inProgress:
        return 'An earlier Apple request is still finishing. Wait for it to close before trying again, or use eero or Advanced.';
      default:
        return 'Checking saved credentials…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Set up network access'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Access lets this app check a router against your network. It does not change the network. Credentials stay in memory for this session.'),
              const SizedBox(height: 16),
              if (_route == _Route.choose) ...[
                const Text('How would you like to get access?'),
                const SizedBox(height: 8),
                if (_showAppleRoute)
                  ListTile(
                    key: const Key('live-apple-route'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use saved Apple credentials'),
                    subtitle: const Text('Requires your permission'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _chooseApple,
                  ),
                ListTile(
                  key: const Key('live-eero-route'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Copy from the eero app'),
                  subtitle:
                      const Text('Guided copy and paste from Thread settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _choose(_Route.eero),
                ),
                ListTile(
                  key: const Key('live-advanced-route'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Advanced: enter a dataset'),
                  subtitle: const Text(
                      'For people who already have the complete dataset'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _choose(_Route.advanced),
                ),
              ] else ...[
                TextButton.icon(
                  onPressed: _importing || _fetchingApple || _checkingApple
                      ? null
                      : () => _choose(_Route.choose),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Other ways to get access'),
                ),
                const SizedBox(height: 8),
                if (_route == _Route.apple) ...[
                  Text('Saved Apple credentials',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_appleStatusMessage(_appleStatus),
                      key: const Key('live-apple-status')),
                ] else if (_route == _Route.eero) ...[
                  Text('Copy from the eero app',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      '1. Open the eero app and find its Thread settings. The path may differ by app version.'),
                  const SizedBox(height: 8),
                  const Text(
                      '2. Touch and hold Active operational dataset to copy it.'),
                  const SizedBox(height: 8),
                  const Text(
                      '3. Return here and paste the copied dataset below.'),
                  const SizedBox(height: 8),
                  const Text(
                      'The separate Thread Network Key is insufficient. Do not regenerate credentials for this check.'),
                ] else ...[
                  Text('Advanced: complete dataset',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      'Enter a complete Active Operational Dataset as hex. A Network Key alone cannot be imported.'),
                ],
                if (_route != _Route.apple) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('live-dataset-input'),
                    controller: _controller,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: _route == _Route.eero
                          ? 'Paste copied dataset'
                          : 'Dataset hex',
                    ),
                  ),
                ],
                if (_failed) ...[
                  const SizedBox(height: 12),
                  Text(
                    _route == _Route.apple
                        ? 'Saved credentials could not be imported. Use eero or Advanced to set up access.'
                        : 'Access could not be set up. Check that you copied the complete Active operational dataset and try again.',
                    key: const Key('live-import-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _importing || _closing ? null : _cancel,
            child: const Text('Cancel'),
          ),
          if (_route == _Route.apple &&
              _appleStatus == AppleCredentialStatus.available)
            FilledButton(
              key: const Key('live-apple-allow'),
              onPressed: _fetchingApple || _importing ? null : _fetchApple,
              child:
                  Text(_fetchingApple ? 'Waiting for Apple…' : 'Allow access'),
            ),
          if (_route == _Route.eero || _route == _Route.advanced)
            FilledButton(
              key: const Key('live-import-submit'),
              onPressed: _importing ? null : _submit,
              child: Text(_importing ? 'Checking…' : 'Set up access'),
            ),
        ],
      ),
    );
  }
}
