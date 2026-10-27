import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/credential_setup_dialog.dart';
import 'package:thread_network_tool/home_assistant_credentials.dart';
import 'package:thread_network_tool/live_api.dart';

import 'support/home_assistant_stub.dart';

const imported = LiveState(
    credentialAvailable: true,
    credentialNetworkName: 'LabTwo',
    discoveryStatus: 'idle',
    observedAt: null,
    routers: []);
const secondNetwork = HomeAssistantNetwork(
    id: 'second',
    name: 'LabTwo',
    extendedPanId: '8899aabbccddeeff',
    channel: 20,
    panId: '1234');

class FakeHaCredentials implements HomeAssistantCredentials {
  @override
  bool supported = true;
  List<HomeAssistantNetwork> networks = [secondNetwork];
  HomeAssistantFailure? error;
  Completer<String>? pendingFetch;
  int listCalls = 0;
  int fetchCalls = 0;
  int cancelCalls = 0;
  String? fetchedId;
  @override
  Future<List<HomeAssistantNetwork>> connectAndList(String url, String token,
      {bool allowUnencrypted = false}) async {
    listCalls++;
    if (error != null) throw HomeAssistantCredentialException(error!);
    return networks;
  }

  @override
  Future<String> fetchDataset(HomeAssistantNetwork selected) async {
    fetchCalls++;
    fetchedId = selected.id;
    return pendingFetch?.future ?? dataset('LabTwo', '8899aabbccddeeff', 20);
  }

  @override
  void cancel() {
    cancelCalls++;
  }
}

class RealHttpOverrides extends HttpOverrides {}

Future<void> openSetup(WidgetTester tester,
    {HomeAssistantCredentials? provider,
    Future<LiveState> Function(String)? onImport,
    TextScaler? scaler}) async {
  await tester.pumpWidget(MaterialApp(
    builder: scaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child!),
    home: Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => showDialog<LiveState>(
                    context: context,
                    builder: (_) => CredentialSetupDialog(
                        showAppleRoute: false,
                        homeAssistantCredentials: provider,
                        importDataset: onImport ?? (_) async => imported)),
                child: const Text('Open')))),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> connect(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('live-ha-route')));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const Key('live-ha-url')), 'https://ha.invalid');
  await tester.enterText(find.byKey(const Key('live-ha-token')), token);
  await tester.ensureVisible(find.byKey(const Key('live-ha-connect')));
  await tester.tap(find.byKey(const Key('live-ha-connect')));
  await tester.pumpAndSettle();
}

Future<void> selectSecond(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('live-ha-networks')));
  await tester.tap(find.byKey(const Key('live-ha-networks')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('LabTwo').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers optional existing Home Assistant alongside other routes',
      (tester) async {
    await openSetup(tester);
    expect(find.text('Use Home Assistant'), findsOneWidget);
    expect(find.text('Copy from the eero app'), findsOneWidget);
    expect(find.text('Advanced: enter a dataset'), findsOneWidget);
  });

  testWidgets(
      'explicit list, selection and import keep the existing source-role callback',
      (tester) async {
    final provider = FakeHaCredentials();
    final sourceImports = <String>[];
    await openSetup(tester, provider: provider, onImport: (value) async {
      sourceImports.add(value);
      return imported;
    });
    expect(provider.listCalls, 0);
    await connect(tester);
    expect(provider.listCalls, 1);
    expect(provider.fetchCalls, 0);
    expect(sourceImports, isEmpty);
    expect(find.byKey(const Key('live-ha-import')), findsNothing);
    final tokenField =
        tester.widget<TextField>(find.byKey(const Key('live-ha-token')));
    expect(tokenField.obscureText, true);
    expect(tokenField.controller!.text, isEmpty);
    await selectSecond(tester);
    expect(provider.fetchCalls, 0);
    await tester.tap(find.byKey(const Key('live-ha-import')));
    await tester.pumpAndSettle();
    expect(provider.fetchedId, 'second');
    expect(sourceImports, [dataset('LabTwo', '8899aabbccddeeff', 20)]);
    expect(find.byType(CredentialSetupDialog), findsNothing);
  });

  testWidgets(
      'cancel ignores a late credential reply and clears token on reopening',
      (tester) async {
    final provider = FakeHaCredentials()..pendingFetch = Completer<String>();
    final imports = <String>[];
    await openSetup(tester, provider: provider, onImport: (value) async {
      imports.add(value);
      return imported;
    });
    await connect(tester);
    await selectSecond(tester);
    await tester.tap(find.byKey(const Key('live-ha-import')));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    provider.pendingFetch!.complete(dataset('LabTwo', '8899aabbccddeeff', 20));
    await tester.pumpAndSettle();
    expect(imports, isEmpty);
    expect(provider.cancelCalls, greaterThan(0));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-ha-route')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('live-ha-token')))
            .controller!
            .text,
        isEmpty);
  });

  testWidgets('empty and admin failure have specific consumer next steps',
      (tester) async {
    final provider = FakeHaCredentials()..networks = [];
    await openSetup(tester, provider: provider);
    await connect(tester);
    expect(find.byKey(const Key('live-ha-empty')), findsOneWidget);
    expect(find.byKey(const Key('live-ha-import')), findsNothing);
    provider.error = HomeAssistantFailure.adminRequired;
    await tester.enterText(find.byKey(const Key('live-ha-token')), token);
    await tester.ensureVisible(find.byKey(const Key('live-ha-connect')));
    await tester.tap(find.byKey(const Key('live-ha-connect')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('requires an administrator token'), findsOneWidget);
    expect(find.textContaining(token), findsNothing);
  });

  testWidgets('local HTTP asks for an explicit unencrypted-connection decision',
      (tester) async {
    await openSetup(tester, provider: FakeHaCredentials());
    await tester.tap(find.byKey(const Key('live-ha-route')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('live-ha-url')), 'http://127.0.0.1:8123');
    await tester.pump();
    final checkbox = tester
        .widget<CheckboxListTile>(find.byKey(const Key('live-ha-unencrypted')));
    expect(checkbox.value, false);
    expect(find.textContaining('without encryption'), findsOneWidget);
  });

  testWidgets('Home Assistant route fits narrow enlarged-text layout',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openSetup(tester,
        provider: FakeHaCredentials(), scaler: const TextScaler.linear(1.5));
    await tester.ensureVisible(find.byKey(const Key('live-ha-route')));
    await tester.tap(find.byKey(const Key('live-ha-route')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('live-ha-url')), 'http://127.0.0.1:8123');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real local WebSocket selected dataset reaches only the supplied role import',
      (tester) async {
    final stub = (await tester.runAsync(() => HaStub.start()))!;
    final sourceImports = <String>[];
    try {
      await openSetup(tester, onImport: (value) async {
        sourceImports.add(value);
        return imported;
      });
      await tester.tap(find.byKey(const Key('live-ha-route')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('live-ha-url')), stub.url);
      await tester.enterText(find.byKey(const Key('live-ha-token')), token);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('live-ha-unencrypted')));
      await tester.tap(find.byKey(const Key('live-ha-unencrypted')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('live-ha-connect')));
      await tester.runAsync(() => HttpOverrides.runWithHttpOverrides(() async {
            await tester.tap(find.byKey(const Key('live-ha-connect')));
            // Let real loopback IO finish outside the widget fake clock.
            for (var i = 0; i < 100 && stub.commands.length < 2; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }, RealHttpOverrides()));
      await tester.pumpAndSettle();
      expect(stub.commands.map((m) => m['type']),
          ['auth', 'thread/list_datasets']);
      expect(sourceImports, isEmpty);
      await selectSecond(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('live-ha-import')));
        for (var i = 0; i < 100 && stub.commands.length < 3; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(stub.commands.last['dataset_id'], 'second');
      expect(sourceImports, [dataset('LabTwo', '8899aabbccddeeff', 20)]);
      expect(find.byType(CredentialSetupDialog), findsNothing);
    } finally {
      await tester.runAsync(stub.close);
    }
  });
}
