import 'dart:io';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'native/isolated_runtime.dart';
import 'network_move_screen.dart';

/// Deliberately separate from main.dart and production platform routing.
/// Start only through the no-network disposable simulator fixture supervisor.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = IsolatedMoveRuntime.fromEnvironment(Platform.environment);
  final state = await runtime.api.discover();
  runApp(MaterialApp(
    title: 'Thread Network Tool — isolated lab',
    theme: threadTheme(),
    home: NetworkMoveScreen(api: runtime.api, initialState: state),
  ));
}
