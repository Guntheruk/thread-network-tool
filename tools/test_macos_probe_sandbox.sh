#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS required' >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmake_bin="${TNT_CMAKE_BIN:-/Users/richard/2026-10-24/new-chat/work/thread-probe/.venv/lib/python3.13/site-packages/cmake/data/bin/cmake}"
flutter_bin="${TNT_FLUTTER_BIN:-/Users/richard/thread/.tooling/flutter/bin/flutter}"
source_dir="${TNT_COMMISSIONER_SOURCE:-$root/build/mac-fixture-dep}"
native_build="${TNT_NATIVE_BUILD_DIR:-$root/build/mac-fixture-native}"
output_dir="${TNT_OUTPUT_DIR:-$root/build/mac-probe-package-$(date +%Y%m%d-%H%M%S)}"
"$cmake_bin" -S "$root" -B "$native_build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' \
  -DTNT_BUILD_TESTS=OFF -DTNT_WITH_COMMISSIONER=ON \
  -DTNT_BUILD_MACOS_PROBE_FIXTURE=ON -DTNT_BUILD_MOVE_LAB=OFF \
  -DTNT_BUILD_APP_MOVE_LAB=OFF -DTNT_BUILD_MOVE_JOURNAL=OFF \
  "-DTNT_COMMISSIONER_SOURCE=$source_dir" >/dev/null
"$cmake_bin" --build "$native_build" --target tnt-macos-probe-fixture --parallel 4 >/dev/null
if [[ ! -d "$output_dir" ]]; then
  TNT_CMAKE_BIN="$cmake_bin" TNT_FLUTTER_BIN="$flutter_bin" \
  TNT_COMMISSIONER_SOURCE="$source_dir" TNT_NATIVE_BUILD_DIR="$native_build" \
  TNT_OUTPUT_DIR="$output_dir" TNT_FLUTTER_TARGET=lib/macos_probe_sandbox_main.dart \
  "$root/tools/build_macos_app.sh"
fi
python3 - "$output_dir" "$native_build/tnt-macos-probe-fixture" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys

package = Path(sys.argv[1])
fixture_exe = sys.argv[2]
apps = list(package.glob('*.app'))
assert len(apps) == 1
app = apps[0]
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
parent = app / 'Contents/MacOS' / info['CFBundleExecutable']
helper = app / 'Contents/Helpers/thread-network'
for binary in (app, helper):
    subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
assert helper.is_file()
results = []
for case in ('success', 'identity_mismatch', 'wrong_credential', 'timeout'):
    fixture = None
    timeout_socket = None
    if case != 'timeout':
        fixture = subprocess.Popen([fixture_exe], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, text=True)
        ready = json.loads(fixture.stdout.readline())
        assert ready['event'] == 'ready' and 1 <= ready['port'] <= 65535
        port = ready['port']
    else:
        timeout_socket = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        timeout_socket.bind(('::1', 0))
        port = timeout_socket.getsockname()[1]
    env = dict(os.environ, TNT_PROBE_SCENARIO=case, TNT_PROBE_PORT=str(port))
    try:
        run = subprocess.run([str(parent)], env=env, capture_output=True,
                             text=True, timeout=48)
        lines = [line.split('TNT_SANDBOX_PROBE ', 1)[1] for line in run.stdout.splitlines()
                 if line.startswith('TNT_SANDBOX_PROBE ')]
        assert len(lines) == 1, (case, 'missing fixed result')
        result = json.loads(lines[0])
        assert result['scenario'] == case and run.returncode == 0, (case, result, run.returncode)
    finally:
        if timeout_socket is not None:
            timeout_socket.close()
        if fixture is not None:
            fixture.terminate()
            try:
                fixture.wait(timeout=3)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()
            count_lines = fixture.stdout.readlines()
            counts = json.loads(count_lines[-1]) if count_lines else {}
        else:
            counts = {'active_get': 0, 'pending_get': 0, 'rejected': 0}
    if case == 'success':
        assert (result['status'], result['authenticated'], result['identity_match'],
                result['active_status'], result['pending_status']) == \
               ('completed', True, 'match', 'read', 'empty')
        assert counts['active_get'] == 1 and counts['pending_get'] == 1
    elif case == 'identity_mismatch':
        assert result['authenticated'] is True and result['identity_match'] == 'mismatch'
        assert counts['active_get'] == 1 and counts['pending_get'] == 1
    elif case == 'wrong_credential':
        # The bounded helper may classify a rejected DTLS handshake as timeout.
        # The fixture's failed-handshake count proves no authenticated read.
        assert result['authenticated'] is not True
        assert counts['active_get'] == 0 and counts['pending_get'] == 0
        assert counts['handshakes'] == 0 and counts['dtls_errors'] >= 1
    else:
        assert result['status'] == 'timeout'
    assert counts['rejected'] == 0
    results.append({'case': case, 'result': result, 'counts': counts})
evidence = {'schema_version': 1, 'package_signature': 'strict_verified',
            'helper_signature': 'strict_verified', 'fixture_bind': '::1',
            'results': results}
path = package / 'macos-probe-sandbox-evidence.json'
path.write_text(json.dumps(evidence, sort_keys=True, indent=2) + '\n')
print(json.dumps({'status': 'passed', 'evidence': str(path)}, sort_keys=True))
PY
