import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/apple_credentials.dart';
import 'package:thread_network_tool/credential_setup_dialog.dart';
import 'package:thread_network_tool/live_api.dart';

class FakeAppleCredentials extends AppleCredentials {
  FakeAppleCredentials() : super(supportedPlatform: false);

  AppleCredentialResult availabilityResult =
      const AppleCredentialResult(AppleCredentialStatus.available);
  AppleCredentialResult fetchResult = const AppleCredentialResult(
      AppleCredentialStatus.available,
      datasetHex: 'AABB');
  Future<AppleCredentialResult> Function()? onFetch;
  int availabilityCalls = 0;
  int fetchCalls = 0;
  int cancelCalls = 0;

  @override
  Future<AppleCredentialResult> availability() async {
    availabilityCalls++;
    return availabilityResult;
  }

  @override
  Future<AppleCredentialResult> fetchPreferred() async {
    fetchCalls++;
    return onFetch == null ? fetchResult : onFetch!();
  }

  @override
  Future<void> cancelFetch() async {
    cancelCalls++;
  }
}

const importedState = LiveState(
  credentialAvailable: true,
  credentialNetworkName: 'SavedMesh',
  discoveryStatus: 'idle',
  observedAt: null,
  routers: [],
);

Future<void> openSetup(WidgetTester tester, FakeAppleCredentials provider,
    Future<LiveState> Function(String) onImport,
    {TextScaler? textScaler}) async {
  await tester.pumpWidget(MaterialApp(
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
    home: Scaffold(
      body: Builder(
        builder: (context) => FilledButton(
          key: const Key('open-setup'),
          onPressed: () => showDialog<LiveState>(
            context: context,
            barrierDismissible: false,
            builder: (_) => CredentialSetupDialog(
              importDataset: onImport,
              appleCredentials: provider,
              showAppleRoute: true,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open-setup')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Apple fetch waits for explicit Allow access and imports once',
      (tester) async {
    final provider = FakeAppleCredentials();
    final imports = <String>[];
    await openSetup(tester, provider, (dataset) async {
      imports.add(dataset);
      return importedState;
    });
    expect(provider.availabilityCalls, 0);
    expect(provider.fetchCalls, 0);
    await tester.tap(find.byKey(const Key('live-apple-route')));
    await tester.pumpAndSettle();
    expect(provider.availabilityCalls, 1);
    expect(provider.fetchCalls, 0);
    expect(find.textContaining('tap Check'), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-apple-allow')));
    await tester.pumpAndSettle();
    expect(provider.fetchCalls, 1);
    expect(imports, ['AABB']);
    expect(find.byKey(const Key('live-apple-status')), findsNothing);
  });

  for (final status in [
    AppleCredentialStatus.permissionDenied,
    AppleCredentialStatus.accessNotConfigured,
    AppleCredentialStatus.noCredentials,
    AppleCredentialStatus.timedOut,
  ]) {
    testWidgets('Apple $status has a safe next step', (tester) async {
      final provider = FakeAppleCredentials()
        ..availabilityResult = AppleCredentialResult(status);
      var imports = 0;
      await openSetup(tester, provider, (_) async {
        imports++;
        return importedState;
      });
      await tester.tap(find.byKey(const Key('live-apple-route')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-apple-allow')), findsNothing);
      expect(find.textContaining('eero or Advanced'), findsOneWidget);
      expect(provider.fetchCalls, 0);
      expect(imports, 0);
      await tester.tap(find.text('Other ways to get access'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live-eero-route')), findsOneWidget);
      expect(find.byKey(const Key('live-advanced-route')), findsOneWidget);
    });
  }

  testWidgets('cancel during Apple consent prevents later import',
      (tester) async {
    final pending = Completer<AppleCredentialResult>();
    final provider = FakeAppleCredentials()..onFetch = () => pending.future;
    var imports = 0;
    await openSetup(tester, provider, (_) async {
      imports++;
      return importedState;
    });
    await tester.tap(find.byKey(const Key('live-apple-route')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-apple-allow')));
    await tester.pump();
    expect(provider.fetchCalls, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(provider.cancelCalls, 1);
    pending.complete(const AppleCredentialResult(
        AppleCredentialStatus.available,
        datasetHex: 'AABB'));
    await tester.pumpAndSettle();
    expect(imports, 0);
  });

  testWidgets('malformed provider data is rejected without displaying it',
      (tester) async {
    final provider = FakeAppleCredentials()
      ..fetchResult = const AppleCredentialResult(
          AppleCredentialStatus.available,
          datasetHex: 'SECRET-invalid');
    var imports = 0;
    await openSetup(tester, provider, (_) async {
      imports++;
      return importedState;
    });
    await tester.tap(find.byKey(const Key('live-apple-route')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-apple-allow')));
    await tester.pumpAndSettle();
    expect(imports, 0);
    expect(find.byKey(const Key('live-import-error')), findsOneWidget);
    expect(find.textContaining('SECRET-invalid'), findsNothing);
  });

  testWidgets('Apple route fits narrow layout with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = FakeAppleCredentials();
    await openSetup(tester, provider, (_) async => importedState,
        textScaler: const TextScaler.linear(2));
    await tester.ensureVisible(find.byKey(const Key('live-apple-route')));
    await tester.tap(find.byKey(const Key('live-apple-route')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-apple-allow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
