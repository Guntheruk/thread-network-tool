#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS required' >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="${TNT_MAC_MOVE_PACKAGE:?set TNT_MAC_MOVE_PACKAGE to a fresh signed test-target package}"
peer="${TNT_MAC_MOVE_PEER:-$root/build/mac-fixture-native/tnt-mac-move-write-fixture}"
python3 - "$package" "$peer" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import secrets
import select
import signal
import socket
import subprocess
import sys
import time

package, peer = Path(sys.argv[1]), Path(sys.argv[2])
apps = list(package.glob('*.app'))
assert len(apps) == 1 and peer.is_file()
app = apps[0]
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
parent = app / 'Contents/MacOS' / info['CFBundleExecutable']
worker = app / 'Contents/Helpers/tnt-mac-move-worker'
journal = app / 'Contents/Helpers/thread-move-journal'
for binary in (app, worker, journal):
    subprocess.run(['codesign', '--verify', '--strict', str(binary)],
                   check=True, capture_output=True)
def entitlements(path):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)],
                            check=True, capture_output=True)
    return plistlib.loads(result.stdout)
outer = entitlements(app)
assert outer['com.apple.security.app-sandbox'] is True
assert outer['com.apple.security.network.client'] is True
assert outer['com.apple.security.network.server'] is True
for binary in (worker, journal):
    rights = entitlements(binary)
    assert rights['com.apple.security.app-sandbox'] is True
    assert rights['com.apple.security.inherit'] is True

def start(role, mode='accept', port=None):
    args = [str(peer), role, mode]
    if port is not None:
        args.append(str(port))
    child = subprocess.Popen(args, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True)
    ready = json.loads(child.stdout.readline())
    assert ready['event'] == 'ready' and 1 <= ready['port'] <= 65535
    return child, ready['port']

def stop(child):
    child.send_signal(signal.SIGTERM)
    row = json.loads(child.stdout.readline())
    child.wait(timeout=5)
    assert row['event'] == 'counts'
    return {key: row[key] for key in (
        'active_get', 'pending_get', 'petition', 'pending_set',
        'rejected', 'handshakes', 'dtls_errors')}

def event(child, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        ready, _, _ = select.select([child.stdout], [], [],
                                    min(1, deadline - time.monotonic()))
        if not ready:
            if child.poll() is not None:
                break
            continue
        line = child.stdout.readline()
        if not line:
            break
        if line.startswith('TNT_MAC_SANDBOX '):
            row = json.loads(line.removeprefix('TNT_MAC_SANDBOX '))
            assert set(row).issubset({
                'stage', 'scenario', 'capabilities', 'journal_initialized',
                'authenticated_snapshots', 'fence_persisted', 'worker_exit',
                'disposition', 'reason', 'petitions', 'pending_set_invocations',
                'configuration_read', 'converged',
                'original_source_unchanged_rejected', 'target_unchanged',
                'source_count'})
            return row
    raise AssertionError('signed parent produced no fixed event')

results = []
for case in ('accept', 'reject', 'fence_mismatch', 'changed_target',
             'silent_target'):
    sources = [start('source'), start('source')]
    target = start('target')
    ports = [entry[1] for entry in sources]
    target_port = target[1]
    env = dict(os.environ, TNT_MOVE_SCENARIO=case,
               TNT_MOVE_SOURCE_PORTS=','.join(map(str, ports)),
               TNT_MOVE_TARGET_PORT=str(target_port),
               TNT_MOVE_NONCE=secrets.token_hex(8))
    child = subprocess.Popen([str(parent)], env=env, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             text=True)
    silent_socket = None
    dispatch_counts = None
    observation_counts = None
    try:
        inspected = event(child, 120)
        assert inspected == {'stage': 'inspected', 'scenario': case,
                             'capabilities': True, 'journal_initialized': True,
                             'authenticated_snapshots': True}
        inspect_counts = [stop(entry[0]) for entry in sources] + [stop(target[0])]
        sources, target = [], None
        assert all(row['pending_set'] == 0 and row['petition'] == 0
                   for row in inspect_counts)
        sources = [start('source', 'reject' if case == 'reject'
                         else 'accept', port=port)
                   for port in ports]
        if case == 'changed_target':
            target = start('source', port=target_port)
        elif case == 'silent_target':
            silent_socket = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
            silent_socket.bind(('::1', target_port))
            target = None
        else:
            target = start('target', port=target_port)
        child.stdin.write('continue\n')
        child.stdin.flush()
        dispatched = event(child, 180)
        dispatch_counts = [stop(entry[0]) for entry in sources]
        sources = []
        if target is not None:
            dispatch_counts.append(stop(target[0]))
            target = None
        else:
            dispatch_counts.append({'active_get': 0, 'pending_get': 0,
                                    'petition': 0, 'pending_set': 0,
                                    'rejected': 0, 'handshakes': 0,
                                    'dtls_errors': 0})
        if case in ('accept', 'reject'):
            sources = [start('target' if case == 'accept' else 'source',
                             port=port) for port in ports]
            target = start('target', port=target_port)
            child.stdin.write('continue\n')
            child.stdin.flush()
            observed = event(child, 150)
            assert observed['stage'] == 'observed'
            assert observed['configuration_read'] is True
            assert observed['target_unchanged'] is True
            assert observed['source_count'] == len(ports)
            if case == 'accept':
                assert observed['converged'] is True
            else:
                assert observed['original_source_unchanged_rejected'] is True
            observation_counts = [stop(entry[0]) for entry in sources] + [stop(target[0])]
            sources, target = [], None
            assert all(row['petition'] == 0 and row['pending_set'] == 0
                       for row in observation_counts)
        child.wait(timeout=5)
        assert child.returncode == 0 and dispatched['stage'] == 'dispatched'
        assert dispatched['scenario'] == case and dispatched['fence_persisted'] is True
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        if silent_socket is not None:
            silent_socket.close()
        for entry in sources:
            stop(entry[0])
        if target is not None:
            stop(target[0])
    assert dispatch_counts is not None
    mutations = sum(row['pending_set'] for row in dispatch_counts)
    assert dispatch_counts[2]['petition'] == 0
    assert dispatch_counts[2]['pending_set'] == 0
    if case == 'accept':
        assert dispatched['disposition'] == 'accepted'
        assert dispatched['pending_set_invocations'] == 1 and mutations == 1
    elif case == 'reject':
        assert dispatched['disposition'] == 'rejected'
        assert dispatched['pending_set_invocations'] == 1 and mutations == 1
    else:
        assert mutations == 0 and dispatched['disposition'] != 'accepted'
    results.append({'case': case, 'inspect_counts': inspect_counts,
                    'dispatch_counts': dispatch_counts,
                    'observation_counts': observation_counts,
                    'outcome': dispatched})

evidence = {'schema_version': 1, 'fixture_bind': '::1',
            'signed_parent_and_helpers': True,
            'parent_sandbox_network_client_server': True,
            'worker_and_journal_inherit_sandbox': True,
            'results': results}
path = package / 'macos-move-sandbox-evidence.json'
path.write_text(json.dumps(evidence, sort_keys=True, indent=2) + '\n')
print(json.dumps({'status': 'passed', 'evidence': str(path)}, sort_keys=True))
PY
