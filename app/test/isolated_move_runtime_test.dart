// Run only through tools/lab/commissioner/app_fixture.py inside the isolated
// Linux image. Every native call below is a real child/Commissioner operation.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/live_api.dart';
import 'package:thread_network_tool/native/isolated_runtime.dart';
import 'package:thread_network_tool/network_move_screen.dart';

void main() {
  final enabled = Platform.isLinux &&
      Platform.environment.containsKey('TNT_FIXTURE_SOCKET');
  testWidgets('actual screen commits one isolated native move and recovers',
      (tester) async {
    String env(String key) =>
        Platform.environment[key] ??
        (throw StateError('missing isolated runtime configuration'));
    final runtime = IsolatedMoveRuntime.fromEnvironment(Platform.environment);
    final fixture = runtime.fixture;
    final bootstrap = await tester.runAsync(() => fixture.call('bootstrap'));
    if (bootstrap == null) throw StateError('missing fixture bootstrap');
    final source = bootstrap['source_dataset'] as String;
    final target = bootstrap['target_dataset'] as String;
    final move = runtime.adapter;
    move.onPreparationFailure =
        (failure) => stdout.writeln(failure.fixtureMarker);
    final session = runtime.session;
    final api = runtime.api;
    expect(api.executionAvailable, isTrue);

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> settleReal({int seconds = 120}) async {
      final until = DateTime.now().add(Duration(seconds: seconds));
      do {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
        if (find.byKey(const Key('move-busy')).evaluate().isEmpty &&
            find.byKey(const Key('move-execution-busy')).evaluate().isEmpty) {
          return;
        }
      } while (DateTime.now().isBefore(until));
      throw StateError('isolated UI action deadline');
    }

    Future<void> tap(String key) async {
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.runAsync(() async {
        await tester.tap(finder);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await settleReal();
    }

    void event(String phase) => stdout.writeln('TNT_APP_EVENT $phase');

    // Import through the actual role-bound setup dialog; no fixture auto-import.
    Future<void> import(String role, String dataset) async {
      await tap('move-$role-access');
      await tap('live-advanced-route');
      await tester.enterText(
          find.byKey(const Key('live-dataset-input')), dataset);
      await tap('live-import-submit');
    }

    final phase = env('TNT_APP_PHASE');
    if (phase == 'dispatch') {
      final discovered = await tester.runAsync(api.discover);
      if (discovered == null) throw StateError('no fixture discovery');
      expect(discovered.routers.length, 3);
      final targetRouter = discovered.routers
          .singleWhere((router) => router.serviceName == 'Isolated target 1');
      final sourceRouters = discovered.routers
          .where((router) => router.id != targetRouter.id)
          .toList();
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
            home: NetworkMoveScreen(api: api, initialState: discovered)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settleReal();
      event('opened');
      await import('target', target);
      event('import_target');
      await tap('move-target-${targetRouter.id}');
      await tap('move-check-target');
      event('target_read');
      await import('source', source);
      event('import_source');
      for (final router in sourceRouters) {
        await tap('move-check-source-${router.id}');
      }
      event('source_read');
      await tap('move-empty-source-attestation');
      await tap('move-prepare');
      final publicPlan = await api.currentNetworkMovePlan();
      expect(publicPlan?.readyForLabReview, isTrue);
      event('review');
      await tap('move-execution-prepare');
      expect(find.byKey(const Key('move-execution-confirm')), findsOneWidget);
      event('native_prepare');
      // Source and target bytes must never appear in the public review/status.
      expect(jsonEncode(session.currentReview).contains(source), isFalse);
      expect(jsonEncode(session.currentReview).contains(target), isFalse);
      await tap('move-execution-confirm');
      event('native_confirm');
      final submitted = await tester.runAsync(api.currentExecution);
      expect(submitted, isNotNull);
      expect(
          submitted!.disposition,
          env('TNT_FIXTURE_SCENARIO') == 'lost-api-result'
              ? 'uncertain'
              : 'accepted');
      expect(move.dispatchLaunches, 1);
      expect(move.lastDispatchPetitions, 1);
      expect(move.lastDispatchSetInvocations, 1);
      event('dispatch_complete');
      expect(find.byKey(const Key('move-execution-confirm')), findsNothing);
      await tester.runAsync(() async {
        var refused = false;
        try {
          await api.confirmExecution(publicPlan!.reviewId);
        } catch (_) {
          refused = true;
        }
        expect(refused, isTrue);
      });
      expect(move.dispatchLaunches, 1);

      // The supervisor terminates this Flutter process after a clean test exit,
      // then launches the recovery phase against these same simulator processes.
      await tap('move-execution-stop');
      expect((await tester.runAsync(api.currentExecution))?.stage,
          'observation_stopped');
      event('stopped');
      await tester.pumpWidget(const SizedBox.shrink());
      session.clear();
      return;
    }
    expect(phase, 'recover');
    final recovered = await tester.runAsync(api.currentExecution);
    expect(recovered, isNotNull);
    expect(recovered?.stage, 'observation_stopped');
    expect(
        recovered?.disposition,
        env('TNT_FIXTURE_SCENARIO') == 'lost-api-result'
            ? 'uncertain'
            : 'accepted');
    expect(move.dispatchLaunches, 0);
    event('restored');
    await tester.runAsync(() => api.credentialsForRole('source', source));
    final restoredState =
        await tester.runAsync(() => api.credentialsForRole('target', target));
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          home: NetworkMoveScreen(api: api, initialState: restoredState!)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settleReal();
    await tap('move-execution-resume');
    event('observing');
    // Continuous fresh real samples, never wall-clock acceleration. The native
    // stack keeps its normal 300-second key-change delay.
    final end = DateTime.now().add(const Duration(seconds: 480));
    NetworkMoveExecutionStatus? outcome;
    while (DateTime.now().isBefore(end)) {
      await tap('move-execution-check');
      outcome = await tester
          .runAsync<NetworkMoveExecutionStatus?>(api.currentExecution);
      if (outcome?.stage == 'verified_complete') break;
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 5)));
      await tester.pump();
    }
    expect(outcome?.stage, 'verified_complete');
    event('verified');
    expect(move.dispatchLaunches, 0);
    final metrics = await tester.runAsync(() => fixture.call('metrics'));
    for (final key in [
      'source_full_match_target',
      'target_unchanged',
      'source_no_pending',
      'target_no_pending',
      'same_partition',
      'source_router_roles',
      'connectivity_verified'
    ]) {
      expect(metrics?[key], isTrue, reason: 'independent oracle $key');
    }
    // Every persistent private recovery file must omit dataset/secret material.
    for (final directory in [
      env('TNT_MOVE_JOURNAL_DIRECTORY'),
      env('TNT_MOVE_LIFECYCLE_DIRECTORY')
    ]) {
      for (final file in Directory(directory).listSync().whereType<File>()) {
        final text = file.readAsStringSync();
        expect(text.contains(source), isFalse);
        expect(text.contains(target), isFalse);
        for (final dataset in [source, target]) {
          final bytes = <int>[
            for (var i = 0; i < dataset.length; i += 2)
              int.parse(dataset.substring(i, i + 2), radix: 16)
          ];
          for (var offset = 0; offset < bytes.length;) {
            final type = bytes[offset++], size = bytes[offset++];
            if (type == 4 || type == 5) {
              final secret = bytes
                  .sublist(offset, offset + size)
                  .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                  .join();
              expect(text.contains(secret), isFalse);
            }
            offset += size;
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    event('redaction');
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 15)));
}
