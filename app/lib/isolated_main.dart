import 'dart:io';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'native/isolated_runtime.dart';
import 'native_live_api.dart';
import 'network_move_screen.dart';

/// Deliberately separate from main.dart and production platform routing.
/// Start only through the no-network disposable simulator fixture supervisor.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = IsolatedMoveRuntime.fromEnvironment(Platform.environment);
  runApp(await bootstrapIsolatedApplication(runtime.api));
}

/// Shared startup route; the regression exercises this exact main() dependency.
Future<Widget> bootstrapIsolatedApplication(NativeLiveApi api) async {
  // Local state cannot depend on a live fixture. The mounted screen restores
  // the durable journal before any explicit discovery/read request.
  final state = await api.state();
  return MaterialApp(
    title: 'Thread Network Tool — isolated lab',
    theme: threadTheme(),
    home: NetworkMoveScreen(api: api, initialState: state),
  );
}
