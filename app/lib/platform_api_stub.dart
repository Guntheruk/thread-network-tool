import 'live_api.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// This app has one route. Keep the browser fragment as a session capability
/// instead of letting Flutter's default hash routing consume and rewrite it.
void configureRouting() => setUrlStrategy(null);

Future<LiveApi?> platformLiveApi() async => null;
