import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/native/session.dart';
import 'package:thread_network_tool/native_live_api.dart';
import 'package:thread_network_tool/network_move_screen.dart';

const _sourceXpan = '1111111111111111';
const _targetXpan = '2222222222222222';
const _sourceStamp = '0000000000000011';
const _targetStamp = '0000000000000022';

class _ReadFixture {
  _ReadFixture({this.pendingSecondSource = false});

  final bool pendingSecondSource;
  final verbs = <String>[];

  Future<NativeReply> call(List<String> args, String? credential) async {
    verbs.add(args.first);
    if (!{'inspect', 'discover', 'probe'}.contains(args.first)) {
      fail('A network-changing native command was attempted');
    }
    if (args.first == 'inspect') {
      expect(credential, anyOf('aa', 'bb'));
      final source = credential == 'aa';
      return NativeReply(0, {
        'schema_version': 1,
        'valid': true,
        'network_name': source ? 'SourceMesh' : 'TargetMesh',
        'extended_pan_id': source ? _sourceXpan : _targetXpan,
        'channel': 15,
        'active_timestamp': source ? _sourceStamp : _targetStamp,
      });
    }
    if (args.first == 'discover') {
      expect(credential, isNull);
      return const NativeReply(0, {
        'schema_version': 1,
        'discovery_status': 'completed',
        'routers': [
          {
            'service_name': 'Source router one',
            'network_name': 'SourceMesh',
            'extended_pan_id': _sourceXpan,
            'address': '192.168.40.11',
            'port': 49111,
          },
          {
            'service_name': 'Source router two',
            'network_name': 'SourceMesh',
            'extended_pan_id': _sourceXpan,
            'address': '192.168.40.12',
            'port': 49112,
          },
          {
            'service_name': 'Target router',
            'network_name': 'TargetMesh',
            'extended_pan_id': _targetXpan,
            'address': '192.168.40.13',
            'port': 49113,
          },
        ],
      });
    }
    expect(args, hasLength(3));
    final source = args[1] != '192.168.40.13';
    expect(credential, source ? 'aa' : 'bb');
    return NativeReply(0, {
      'schema_version': 1,
      'probe_status': 'completed',
      'authenticated': true,
      'identity_match': 'match',
      'active_status': 'read',
      'pending_status': pendingSecondSource && args[1] == '192.168.40.12'
          ? 'present'
          : 'empty',
      'active_network_name': source ? 'SourceMesh' : 'TargetMesh',
      'active_extended_pan_id': source ? _sourceXpan : _targetXpan,
      'active_channel': 15,
      'active_timestamp': source ? _sourceStamp : _targetStamp,
    });
  }
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 250);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<NativeLiveApi> _runReview(
    WidgetTester tester, _ReadFixture fixture) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = NativeLiveApi(native: fixture.call);
  await api.credentialsForRole('source', 'aa');
  await api.credentialsForRole('target', 'bb');
  final discovered = await api.discover();
  expect(discovered.routers.length, 3);
  final sourceA = discovered.routers[0].id;
  final sourceB = discovered.routers[1].id;
  final target = discovered.routers[2].id;

  await tester.pumpWidget(MaterialApp(
    home: NetworkMoveScreen(api: api, initialState: discovered),
  ));
  await tester.pumpAndSettle();
  await _tapVisible(tester, Key('move-target-$target'));
  await _tapVisible(tester, const Key('move-check-target'));
  await _tapVisible(tester, Key('move-check-source-$sourceA'));
  await _tapVisible(tester, Key('move-check-source-$sourceB'));
  await _tapVisible(tester, const Key('move-empty-source-attestation'));
  await _tapVisible(tester, const Key('move-prepare'));
  final review = find.byKey(const Key('move-review'));
  if (review.evaluate().isEmpty) {
    await tester.scrollUntilVisible(review, 250);
  } else {
    await tester.ensureVisible(review);
  }
  await tester.pumpAndSettle();

  expect(find.descendant(of: review, matching: find.text('Source router one')),
      findsOneWidget);
  expect(find.descendant(of: review, matching: find.text('Source router two')),
      findsOneWidget);
  expect(
      find.descendant(
          of: review, matching: find.text('Observed source routers (2)')),
      findsOneWidget);
  expect(
      find.descendant(
          of: review, matching: find.text('Propagation delay: 5 minutes')),
      findsOneWidget);
  expect(
      find.descendant(
          of: review,
          matching:
              find.textContaining('Choose a supported propagation delay')),
      findsNothing);
  expect(fixture.verbs,
      ['inspect', 'inspect', 'discover', 'probe', 'probe', 'probe']);
  expect(tester.takeException(), isNull);
  return api;
}

void main() {
  testWidgets('real planner prepares a ready network-wide review at UI default',
      (tester) async {
    final fixture = _ReadFixture();
    await _runReview(tester, fixture);
    final review = find.byKey(const Key('move-review'));
    expect(
        find.descendant(
            of: review,
            matching:
                find.textContaining('Evidence ready for separate lab review')),
        findsOneWidget);
  });

  testWidgets('one pending source router blocks the real plan', (tester) async {
    final fixture = _ReadFixture(pendingSecondSource: true);
    await _runReview(tester, fixture);
    final review = find.byKey(const Key('move-review'));
    expect(
        find.descendant(
            of: review,
            matching: find.textContaining('More evidence is needed')),
        findsOneWidget);
    expect(
        find.descendant(
            of: review,
            matching:
                find.textContaining('A source router has a pending change')),
        findsOneWidget);
  });

  testWidgets('another screen invalidates a ready review in the shared session',
      (tester) async {
    final fixture = _ReadFixture();
    final api = await _runReview(tester, fixture);
    expect(find.textContaining('Evidence ready for separate lab review'),
        findsOneWidget);

    final secondState = await api.state();
    final navigator =
        Navigator.of(tester.element(find.byType(NetworkMoveScreen)));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => NetworkMoveScreen(api: api, initialState: secondState),
    ));
    await tester.pumpAndSettle();
    await _tapVisible(tester, const Key('move-discover'));
    expect(await api.currentNetworkMovePlan(), isNull);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('Evidence ready for separate lab review'),
        findsNothing);
  });
}
