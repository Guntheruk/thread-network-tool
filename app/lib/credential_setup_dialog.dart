import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'apple_credentials.dart';
import 'live_api.dart';
import 'home_assistant_credentials.dart';

/// Guided, read-only credential import. The API validates the complete dataset;
/// this dialog only rejects obviously malformed input before sending it.
class CredentialSetupDialog extends StatefulWidget {
  const CredentialSetupDialog({
    super.key,
    required this.importDataset,
    this.appleCredentials,
    this.showAppleRoute,
    this.homeAssistantCredentials,
  });

  final Future<LiveState> Function(String dataset) importDataset;
  final AppleCredentials? appleCredentials;
  final bool? showAppleRoute;
  final HomeAssistantCredentials? homeAssistantCredentials;

  @override
  State<CredentialSetupDialog> createState() => _CredentialSetupDialogState();
}

enum _Route { choose, apple, homeAssistant, eero, advanced }

class _CredentialSetupDialogState extends State<CredentialSetupDialog> {
  final TextEditingController _controller = TextEditingController();
  late final AppleCredentials _appleCredentials =
      widget.appleCredentials ?? AppleCredentials();
  late final HomeAssistantCredentials _homeAssistant =
      widget.homeAssistantCredentials ?? HomeAssistantCredentials();
  final TextEditingController _haUrl = TextEditingController();
  final TextEditingController _haToken = TextEditingController();
  List<HomeAssistantNetwork> _haNetworks = const [];
  HomeAssistantNetwork? _haSelected;
  HomeAssistantFailure? _haFailure;
  bool _haBusy = false;
  bool _haListed = false;
  bool _allowUnencryptedHa = false;
  int _haGeneration = 0;
  _Route _route = _Route.choose;
  bool _importing = false;
  bool _checkingApple = false;
  bool _fetchingApple = false;
  bool _closing = false;
  bool _failed = false;
  AppleCredentialStatus? _appleStatus;

  bool get _showAppleRoute =>
      widget.showAppleRoute ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  bool get _showMacAppleLimitNote =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.macOS &&
      !_showAppleRoute;

  @override
  void dispose() {
    _homeAssistant.cancel();
    _haUrl.clear();
    _haToken.clear();
    _haUrl.dispose();
    _haToken.dispose();
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _choose(_Route route) {
    _resetHomeAssistant();
    _haToken.clear();
    _haUrl.clear();
    _allowUnencryptedHa = false;
    _controller.clear();
    setState(() {
      _route = route;
      _failed = false;
      _appleStatus = null;
    });
  }

  void _resetHomeAssistant() {
    _haGeneration++;
    _homeAssistant.cancel();
    _haNetworks = const [];
    _haSelected = null;
    _haFailure = null;
    _haListed = false;
    _haBusy = false;
  }

  Future<void> _listHomeAssistant() async {
    final url = _haUrl.text.trim();
    final token = _haToken.text.trim();
    _haToken.clear();
    final generation = ++_haGeneration;
    setState(() {
      _haBusy = true;
      _haFailure = null;
      _haNetworks = const [];
      _haSelected = null;
      _haListed = false;
    });
    try {
      final networks = await _homeAssistant.connectAndList(url, token,
          allowUnencrypted: _allowUnencryptedHa);
      if (!mounted || _closing || generation != _haGeneration) return;
      setState(() {
        _haNetworks = networks;
        _haListed = true;
      });
    } on HomeAssistantCredentialException catch (error) {
      if (!mounted || _closing || generation != _haGeneration) return;
      setState(() => _haFailure = error.failure);
    } catch (_) {
      if (!mounted || _closing || generation != _haGeneration) return;
      setState(() => _haFailure = HomeAssistantFailure.connectionFailed);
    } finally {
      if (mounted && !_closing && generation == _haGeneration) {
        setState(() => _haBusy = false);
      }
    }
  }

  Future<void> _fetchHomeAssistant() async {
    final selected = _haSelected;
    if (selected == null || _haBusy) return;
    final generation = ++_haGeneration;
    setState(() {
      _haBusy = true;
      _haFailure = null;
    });
    try {
      final dataset = await _homeAssistant.fetchDataset(selected);
      if (!mounted || _closing || generation != _haGeneration) return;
      setState(() {
        _haNetworks = const [];
        _haSelected = null;
        _haListed = false;
      });
      await _importDataset(dataset);
    } on HomeAssistantCredentialException catch (error) {
      if (!mounted || _closing || generation != _haGeneration) return;
      setState(() => _haFailure = error.failure);
    } catch (_) {
      if (!mounted || _closing || generation != _haGeneration) return;
      setState(() => _haFailure = HomeAssistantFailure.connectionFailed);
    } finally {
      if (mounted && !_closing && generation == _haGeneration) {
        setState(() => _haBusy = false);
      }
    }
  }

  String _homeAssistantMessage(HomeAssistantFailure failure) =>
      switch (failure) {
        HomeAssistantFailure.unsupported =>
          'Use the desktop app for Home Assistant access. You can still use eero or Advanced here.',
        HomeAssistantFailure.invalidUrl =>
          'Enter your Home Assistant base address, starting with https:// or http://. Do not put a token in the address.',
        HomeAssistantFailure.unencryptedConsentRequired =>
          'For a local HTTP connection, read and accept the unencrypted connection notice first.',
        HomeAssistantFailure.publicHttpRefused =>
          'Unencrypted access is limited to private local networks or this computer. Use HTTPS for a public address.',
        HomeAssistantFailure.authenticationRejected =>
          'Home Assistant did not accept the token. Use an existing valid token for your chosen server.',
        HomeAssistantFailure.adminRequired =>
          'Home Assistant requires an administrator token to read saved Thread networks.',
        HomeAssistantFailure.threadUnavailable =>
          'This Home Assistant does not offer the Thread credential API. Use eero or Advanced, or check its Thread integration.',
        HomeAssistantFailure.networkNotFound =>
          'That saved network is no longer available. Connect again and choose a network.',
        HomeAssistantFailure.timedOut =>
          'Home Assistant did not respond in time. Check the address and connection, then connect again.',
        HomeAssistantFailure.cancelled =>
          'The Home Assistant request was cancelled.',
        HomeAssistantFailure.invalidData =>
          'Home Assistant returned incomplete or unsupported network data. Nothing was imported.',
        HomeAssistantFailure.identityMismatch =>
          'The retrieved credentials do not match the selected network. Nothing was imported. Connect again to refresh the list.',
        HomeAssistantFailure.connectionFailed =>
          'Could not connect securely to Home Assistant. Check the address, connection and HTTPS certificate, then try again.',
      };

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
    _resetHomeAssistant();
    _haToken.clear();
    _haUrl.clear();
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
                  key: const Key('live-ha-route'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use Home Assistant'),
                  subtitle: const Text(
                      'Optional: read networks saved in your existing server'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _choose(_Route.homeAssistant),
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
                if (_showMacAppleLimitNote) ...[
                  const SizedBox(height: 8),
                  const Text(
                      'To access an Apple Thread network, use complete credentials already saved in Home Assistant or obtained elsewhere. This app cannot retrieve Apple credentials on Mac.'),
                ],
              ] else ...[
                TextButton.icon(
                  onPressed:
                      _importing || _haBusy || _fetchingApple || _checkingApple
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
                ] else if (_route == _Route.homeAssistant) ...[
                  const Text('Use your existing Home Assistant'),
                  const SizedBox(height: 8),
                  const Text(
                      'Home Assistant is optional. This reads only networks already saved in your chosen server; it cannot obtain every Apple or eero network. It does not change Home Assistant or your network.'),
                  const SizedBox(height: 8),
                  if (!_homeAssistant.supported)
                    Text(
                        _homeAssistantMessage(HomeAssistantFailure.unsupported))
                  else ...[
                    TextField(
                      key: const Key('live-ha-url'),
                      controller: _haUrl,
                      enabled: !_haBusy,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                          labelText: 'Home Assistant address',
                          hintText: 'https://your-server'),
                      onChanged: (_) => setState(() {
                        _resetHomeAssistant();
                        _allowUnencryptedHa = false;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('live-ha-token'),
                      controller: _haToken,
                      enabled: !_haBusy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                          labelText: 'Existing access token',
                          helperText:
                              'Requires an administrator token. Kept only for this connection.'),
                      onChanged: (_) => setState(_resetHomeAssistant),
                    ),
                    if (Uri.tryParse(_haUrl.text.trim())?.scheme == 'http')
                      CheckboxListTile(
                        key: const Key('live-ha-unencrypted'),
                        contentPadding: EdgeInsets.zero,
                        value: _allowUnencryptedHa,
                        title: const Text(
                            'I understand this local HTTP connection sends my access token and credentials without encryption. Use only a trusted private network.'),
                        onChanged: _haBusy
                            ? null
                            : (value) => setState(() {
                                  _resetHomeAssistant();
                                  _allowUnencryptedHa = value == true;
                                }),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const Key('live-ha-connect'),
                      onPressed: _haBusy ? null : _listHomeAssistant,
                      child: Text(_haBusy
                          ? 'Waiting for Home Assistant…'
                          : 'Connect and list networks'),
                    ),
                    if (_haListed && _haNetworks.isEmpty)
                      const Text(
                          'No saved Thread networks were found. Home Assistant may not have the credentials you need. Use eero or Advanced; no network was changed.',
                          key: Key('live-ha-empty')),
                    if (_haNetworks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                          'Choose the network to use for this setup. The preferred network is not selected automatically.'),
                      DropdownButton<HomeAssistantNetwork>(
                        key: const Key('live-ha-networks'),
                        isExpanded: true,
                        value: _haSelected,
                        hint: const Text('Choose a saved network'),
                        items: _haNetworks
                            .map((network) => DropdownMenuItem(
                                  value: network,
                                  child: Text(
                                      '${network.name} · channel ${network.channel} · ${network.extendedPanId}',
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: _haBusy
                            ? null
                            : (network) =>
                                setState(() => _haSelected = network),
                      ),
                    ],
                    if (_haFailure != null)
                      Text(_homeAssistantMessage(_haFailure!),
                          key: const Key('live-ha-status')),
                  ],
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
                if (_route == _Route.eero || _route == _Route.advanced) ...[
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
          if (_route == _Route.homeAssistant && _haSelected != null)
            FilledButton(
              key: const Key('live-ha-import'),
              onPressed: _haBusy || _importing ? null : _fetchHomeAssistant,
              child: Text(_importing ? 'Checking…' : 'Import selected network'),
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
