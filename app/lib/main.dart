import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine_service.dart';
import 'app_theme.dart';
import 'live_screen.dart';
import 'live_api.dart';
import 'platform_api_stub.dart' if (dart.library.io) 'platform_api_io.dart'
    as platform;

String? liveSessionFromFragment(String fragment) =>
    RegExp(r'(?:^|[?&])session=([0-9a-f]{64})(?:&|$)')
        .firstMatch(fragment)
        ?.group(1);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  platform.configureRouting();
  final liveApi = await platform.platformLiveApi();
  runApp(ThreadNetworkApp(
    liveSession: liveSessionFromFragment(Uri.base.fragment),
    liveApi: liveApi,
  ));
}

class ThreadNetworkApp extends StatelessWidget {
  const ThreadNetworkApp({
    super.key,
    this.engine = const SyntheticDemoEngineService(),
    this.liveSession,
    this.liveApi,
  });

  final EngineService engine;
  final String? liveSession;
  final LiveApi? liveApi;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thread Network Tool',
      debugShowCheckedModeBanner: false,
      theme: threadTheme(),
      home: liveSession != null
          ? LiveScreen(session: liveSession!)
          : liveApi != null
              ? LiveScreen(api: liveApi)
              : AssessmentScreen(engine: engine),
    );
  }
}

class _Network {
  const _Network({
    required this.name,
    required this.vendor,
    required this.detail,
  });

  final String name;
  final String vendor;
  final String detail;
}

const _fictionalNetworks = <_Network>[
  _Network(
    name: 'HomeMesh',
    vendor: 'Aster Labs',
    detail: 'Border router advertisement',
  ),
  _Network(
    name: 'SpareMesh',
    vendor: 'Harbor Devices',
    detail: 'Border router advertisement',
  ),
];

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key, required this.engine});

  final EngineService engine;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  int _step = 0;
  int _target = 0;
  DatasetInspection? _inspection;
  bool _fixtureUsed = false;

  String get _targetName => _fictionalNetworks[_target].name;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 36 : 18,
                vertical: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(wide),
                  const SizedBox(height: 20),
                  _demoBanner(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 220,
                                child: _steps(vertical: true),
                              ),
                              const SizedBox(width: 26),
                              Expanded(child: _page()),
                            ],
                          )
                        : Column(
                            children: [
                              _steps(vertical: false),
                              const SizedBox(height: 16),
                              Expanded(child: _page()),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool wide) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ThreadColors.blueSoft,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.hub_outlined, color: ThreadColors.blue),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thread Network Tool',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Understand networks. Plan a compatible router join.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (wide) const Chip(label: Text('READ ONLY')),
        ],
      );

  Widget _demoBanner() => Container(
        key: const Key('synthetic-demo-banner'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ThreadColors.subtle,
          border: Border.all(color: ThreadColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: ThreadColors.blue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.engine.isSyntheticDemo
                    ? 'SYNTHETIC DEMO · HomeMesh and SpareMesh are fictional. '
                        'No LAN discovery, authenticated probe, or real credential reading occurs here.'
                    : 'SYNTHETIC NETWORK BOARD · HomeMesh and SpareMesh are fictional. '
                        'Dataset inspection does not discover or authenticate these routers.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _steps({required bool vertical}) {
    const labels = ['Networks', 'Credentials', 'Review'];
    final buttons = List<Widget>.generate(labels.length, (i) {
      final selected = _step == i;
      return Padding(
        padding: EdgeInsets.only(
          right: vertical ? 0 : 6,
          bottom: vertical ? 8 : 0,
        ),
        child: Material(
          color: selected ? ThreadColors.blueSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            key: Key('step-$i'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _step = i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor:
                        selected ? ThreadColors.blue : ThreadColors.border,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : ThreadColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
    return vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buttons,
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: buttons),
          );
  }

  Widget _page() => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: switch (_step) {
            0 => _networksPage(),
            1 => _credentialsPage(),
            _ => _reviewPage(),
          },
        ),
      );

  Widget _intro(String eyebrow, String title, String description) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: ThreadColors.blue,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(description, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 23),
        ],
      );

  Widget _networksPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro(
            'Step 01 / Discover',
            'Choose the network to keep',
            'These fictional advertisements show possible networks. They do not prove access or compatibility.',
          ),
          for (var i = 0; i < _fictionalNetworks.length; i++) ...[
            _networkCard(i),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 10),
          _infoCard(
            Icons.verified_user_outlined,
            'Authentication is separate',
            'Neither router has been authenticated. An advertisement alone cannot confirm its active dataset or join capability.',
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => setState(() => _step = 1),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue to credentials'),
            ),
          ),
        ],
      );

  Widget _networkCard(int index) {
    final network = _fictionalNetworks[index];
    final selected = _target == index;
    return Card(
      child: InkWell(
        key: Key('target-$index'),
        borderRadius: BorderRadius.circular(4),
        onTap: () => setState(() => _target = index),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: ThreadColors.blue,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            network.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (selected) const Chip(label: Text('TARGET')),
                      ],
                    ),
                    Text('${network.vendor} · ${network.detail}'),
                    const SizedBox(height: 13),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children: [
                        _StatusChip('Discovery provisional', Icons.sensors),
                        _StatusChip('Not authenticated', Icons.lock_outline),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _credentialsPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro(
            'Step 02 / Inspect',
            'Inspect authorized credentials',
            'A dataset can establish network identity for assessment. Inspection never changes a router.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(21),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.key_outlined,
                    color: ThreadColors.blue,
                    size: 31,
                  ),
                  const SizedBox(height: 13),
                  Text(
                    'Dataset inspection',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.engine.isSyntheticDemo
                        ? 'Demo mode refuses real credential imports. Try the safe synthetic fixture.'
                        : 'Enter a dataset you are authorized to use. It stays in memory for this session.',
                  ),
                  const SizedBox(height: 17),
                  Wrap(
                    spacing: 10,
                    runSpacing: 9,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('import-dataset'),
                        onPressed: _openImportDialog,
                        icon: const Icon(Icons.input),
                        label: const Text('Import dataset'),
                      ),
                      if (widget.engine is SyntheticDemoEngineService)
                        FilledButton.tonalIcon(
                          key: const Key('safe-fixture'),
                          onPressed: () => setState(() {
                            _inspection =
                                (widget.engine as SyntheticDemoEngineService)
                                    .inspectSafeFixture();
                            _fixtureUsed = true;
                          }),
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('Use synthetic fixture'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_inspection?.accepted == true && _inspection?.metadata != null)
            _inspectedCard(_inspection!.metadata!),
          const SizedBox(height: 14),
          _infoCard(
            Icons.lock_clock_outlined,
            'Local and temporary',
            'Input is masked, held only while inspecting, and cleared when the dialog closes. No credential text appears in errors or reports.',
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => setState(() => _step = 2),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue to review'),
            ),
          ),
        ],
      );

  Widget _inspectedCard(DatasetMetadata metadata) => Card(
        child: Padding(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _fixtureUsed
                    ? 'Synthetic fixture inspected'
                    : 'Dataset inspected',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Network: ${metadata.networkName} · Channel: ${metadata.channel}',
              ),
              Text(
                'Key present: ${metadata.hasNetworkKey ? 'yes' : 'no'} · '
                'PSKc present: ${metadata.hasPskc ? 'yes' : 'no'}',
              ),
              Text('Unknown TLV types: ${metadata.unknownTlvCount}'),
              const SizedBox(height: 9),
              const Text('No router authentication has occurred.'),
            ],
          ),
        ),
      );

  Future<void> _openImportDialog() async {
    final controller = TextEditingController();
    var busy = false;
    var rejected = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import an authorized dataset'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Temporary in-memory inspection only. Input is masked and is not saved.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('dataset-input'),
                  controller: controller,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Dataset hex',
                    hintText: 'Masked input',
                  ),
                ),
                if (widget.engine.isSyntheticDemo) ...[
                  const SizedBox(height: 11),
                  const Text(
                    'Synthetic demo rejects all real imports.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (rejected) ...[
                  const SizedBox(height: 11),
                  const Text(
                    'Dataset was not inspected. Check the input or use the synthetic fixture.',
                    key: Key('import-error'),
                    style: TextStyle(color: ThreadColors.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('inspect-submit'),
              onPressed: busy
                  ? null
                  : () async {
                      final input = controller.text;
                      if (input.isEmpty || input.length > 508) {
                        controller.clear();
                        setDialogState(() => rejected = true);
                        return;
                      }
                      setDialogState(() => busy = true);
                      DatasetInspection result;
                      try {
                        result = await widget.engine.inspectDataset(input);
                      } catch (_) {
                        result = const DatasetInspection.rejected();
                      }
                      if (!dialogContext.mounted) return;
                      controller.clear();
                      if (!result.accepted || result.metadata == null) {
                        setDialogState(() {
                          busy = false;
                          rejected = true;
                        });
                        return;
                      }
                      setState(() {
                        _inspection = result;
                        _fixtureUsed = false;
                      });
                      Navigator.pop(dialogContext);
                    },
              child: const Text('Inspect'),
            ),
          ],
        ),
      ),
    );
    controller.clear();
    controller.dispose();
  }

  Widget _reviewPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro(
            'Step 03 / Review',
            'Review the join plan',
            'The target is $_targetName. The current evidence cannot authorize a migration.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proposed target · $_targetName',
                    key: const Key('review-target'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  const _ReviewLine(
                    'Discovery',
                    'Synthetic example; no live discovery',
                    Icons.sensors,
                  ),
                  const _ReviewLine(
                    'Router authentication',
                    'Not performed',
                    Icons.lock_outline,
                  ),
                  _ReviewLine(
                    'Dataset',
                    _inspection?.accepted == true
                        ? (_fixtureUsed
                            ? 'Synthetic fixture only'
                            : 'Inspected locally')
                        : 'No dataset inspected',
                    Icons.key_outlined,
                  ),
                  if (_inspection?.metadata != null)
                    _ReviewLine(
                      'Target comparison',
                      _inspection!.metadata!.networkName == _targetName
                          ? 'Name matches; identity and router access unverified'
                          : 'Dataset name differs from selected target',
                      Icons.compare_arrows_outlined,
                    ),
                  const _ReviewLine(
                    'Joining support',
                    'Unknown; vendor and lab validation needed',
                    Icons.help_outline,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
          _infoCard(
            Icons.devices_other_outlined,
            'Accessory scope is unknown',
            'Existing accessories may need separate handling. Automatic transfer is optional and has not been established.',
          ),
          const SizedBox(height: 13),
          _infoCard(
            Icons.block_outlined,
            'Migration is gated',
            'Joining is disabled until a compatible router is authenticated and a safe lab join has been validated.',
          ),
          const SizedBox(height: 21),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                key: const Key('report-preview'),
                onPressed: _showReport,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Preview redacted report'),
              ),
              FilledButton.icon(
                key: const Key('join-disabled'),
                onPressed: null,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Join router unavailable'),
              ),
            ],
          ),
        ],
      );

  Widget _infoCard(IconData icon, String title, String body) => Card(
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ThreadColors.blue),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  String _redactedReport() => [
        'Thread Network Tool — read-only assessment',
        widget.engine.isSyntheticDemo
            ? 'Mode: SYNTHETIC DEMO'
            : 'Mode: local assessment',
        'Target: Network ${_target == 0 ? 'A' : 'B'}',
        'Network board: synthetic fictional examples',
        'Discovery: no live discovery',
        'Router authentication: not performed',
        'Dataset: ${_inspection?.accepted == true ? (_fixtureUsed ? 'synthetic fixture' : 'inspected; identity redacted') : 'none'}',
        'Joining support: unknown',
        'Accessory scope: unknown; automatic transfer not established',
        'Migration: disabled pending authenticated compatibility and lab validation',
        'Credentials and network identifiers: redacted',
      ].join('\n');

  Future<void> _showReport() async {
    final report = _redactedReport();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redacted report preview'),
        content: SizedBox(
          width: 500,
          child: SelectableText(report, key: const Key('report-text')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            key: const Key('copy-report'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy redacted report'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: ThreadColors.subtle,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: ThreadColors.blue),
            const SizedBox(width: 10),
            SizedBox(
              width: 145,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
