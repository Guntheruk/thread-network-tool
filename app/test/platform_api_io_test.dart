import 'package:flutter_test/flutter_test.dart';
import 'package:thread_network_tool/platform_api_io.dart';

void main() {
  const runner =
      '/Applications/Thread Network Tool.app/Contents/MacOS/Thread Network Tool';

  test('bundled helper resolves under Contents/Helpers', () {
    final path = resolveNativeEnginePath(
      resolvedExecutable: runner,
      exists: (path) =>
          path ==
          '/Applications/Thread Network Tool.app/Contents/Helpers/thread-network',
    );
    expect(path,
        '/Applications/Thread Network Tool.app/Contents/Helpers/thread-network');
  });

  test('missing bundled helper is unavailable', () {
    expect(
      resolveNativeEnginePath(
        resolvedExecutable: runner,
        exists: (_) => false,
      ),
      isNull,
    );
  });

  test('absolute override wins and a missing override does not fall back', () {
    expect(
      resolveNativeEnginePath(
        resolvedExecutable: runner,
        engineOverride: '/tmp/thread-network',
        exists: (path) => path == '/tmp/thread-network',
      ),
      '/tmp/thread-network',
    );
    expect(
      resolveNativeEnginePath(
        resolvedExecutable: runner,
        engineOverride: '/tmp/missing',
        exists: (path) => path.contains('/Contents/Helpers/'),
      ),
      isNull,
    );
  });

  test('relative override is rejected even when it exists', () {
    expect(
      resolveNativeEnginePath(
        resolvedExecutable: runner,
        engineOverride: 'build/thread-network',
        exists: (_) => true,
      ),
      isNull,
    );
  });
}
