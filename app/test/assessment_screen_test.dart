import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/engine_service.dart';
import 'package:thread_network_tool/main.dart';

class _NativeInspectorStub implements EngineService {
  @override
  bool get isSyntheticDemo => false;

  @override
  Future<DatasetInspection> inspectDataset(String datasetHex) async =>
      const DatasetInspection.rejected();
}

void main() {
  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ThreadNetworkApp());
  }

  testWidgets('demo status stays prominent and describes synthetic data', (
    tester,
  ) async {
    await start(tester);
    expect(find.byKey(const Key('synthetic-demo-banner')), findsOneWidget);
    expect(find.textContaining('SYNTHETIC DEMO'), findsOneWidget);
    expect(find.text('HomeMesh'), findsOneWidget);
    expect(find.text('SpareMesh'), findsOneWidget);
    expect(find.text('Not authenticated'), findsNWidgets(2));
  });

  testWidgets('native inspector does not make fictional discovery look live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ThreadNetworkApp(engine: _NativeInspectorStub()));
    expect(find.textContaining('SYNTHETIC NETWORK BOARD'), findsOneWidget);
    expect(find.text('Discovery provisional'), findsNWidgets(2));
    expect(find.text('Not authenticated'), findsNWidgets(2));
  });

  testWidgets('target selection reaches review and join remains disabled', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byKey(const Key('target-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('step-2')));
    await tester.pump();
    expect(find.text('Proposed target · SpareMesh'), findsOneWidget);
    expect(find.text('Accessory scope is unknown'), findsOneWidget);
    final join = tester.widget<FilledButton>(
      find.byKey(const Key('join-disabled')),
    );
    expect(join.onPressed, isNull);
    await tester.tap(find.byKey(const Key('report-preview')));
    await tester.pumpAndSettle();
    final report = tester
        .widget<SelectableText>(find.byKey(const Key('report-text')))
        .data!;
    expect(report, contains('Target: Network B'));
    expect(report, isNot(contains('SpareMesh')));
    expect(report, contains('Migration: disabled'));
  });

  testWidgets('demo rejects entered credentials without echoing them', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byKey(const Key('step-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-dataset')));
    await tester.pumpAndSettle();
    const secret = 'DEADBEEFDEADBEEF';
    await tester.enterText(find.byKey(const Key('dataset-input')), secret);
    await tester.tap(find.byKey(const Key('inspect-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-error')), findsOneWidget);
    expect(find.text(secret), findsNothing);
  });

  testWidgets('safe fixture is usable but does not imply authentication', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byKey(const Key('target-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('step-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('safe-fixture')));
    await tester.pump();
    expect(find.text('Synthetic fixture inspected'), findsOneWidget);
    expect(find.text('No router authentication has occurred.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('step-2')));
    await tester.pump();
    expect(find.text('Synthetic fixture only'), findsOneWidget);
    expect(
      find.text('Dataset name differs from selected target'),
      findsOneWidget,
    );
    final join = tester.widget<FilledButton>(
      find.byKey(const Key('join-disabled')),
    );
    expect(join.onPressed, isNull);
  });

  testWidgets('compact mobile viewport keeps all steps usable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ThreadNetworkApp());
    expect(find.byKey(const Key('synthetic-demo-banner')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('step-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step-1')));
    await tester.pump();
    expect(find.byKey(const Key('import-dataset')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('step-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step-2')));
    await tester.pump();
    expect(find.byKey(const Key('join-disabled')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('native metadata parser rejects malformed or failed JSON', () {
    expect(
      () =>
          DatasetMetadata.fromEngineJson({'schema_version': 1, 'valid': false}),
      throwsFormatException,
    );
    expect(
      () => DatasetMetadata.fromEngineJson({
        'schema_version': 1,
        'valid': true,
        'network_name': 'Example',
        'channel': '15',
        'has_network_key': true,
        'has_pskc': true,
        'unknown_tlv_types': <int>[],
      }),
      throwsFormatException,
    );

    Map<String, dynamic> valid() => {
          'schema_version': 1,
          'valid': true,
          'network_name': 'Example',
          'channel': 15,
          'has_network_key': true,
          'has_pskc': true,
          'unknown_tlv_types': <int>[],
        };
    for (final change in <void Function(Map<String, dynamic>)>[
      (json) => json['network_name'] = 'This name is over 16 bytes',
      (json) => json['network_name'] = 'Bad\nName',
      (json) => json['channel'] = 27,
      (json) => json['has_pskc'] = false,
      (json) => json['unknown_tlv_types'] = <Object>['bad'],
      (json) => json['unknown_tlv_types'] = <int>[256],
    ]) {
      final json = valid();
      change(json);
      expect(() => DatasetMetadata.fromEngineJson(json), throwsFormatException);
    }
  });
}
