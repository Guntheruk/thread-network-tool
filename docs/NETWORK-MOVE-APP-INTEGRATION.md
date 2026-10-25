# Isolated application network move

This slice connects the actual Flutter screen, `NativeLiveApi`, `LiveSession`,
durable execution controller/journal and Commissioner worker. Its only execution
profile is `openthread-posix-lab-v1`, with a controlled empty software source on
Linux. The default application and default native build remain read-only.

## Application entry and authority

`app/lib/isolated_main.dart` is a separate explicit entry point. It uses the same
`IsolatedMoveRuntime` assembly exercised by the real runtime test. Production
`platformLiveApi()` does not construct that assembly or inspect these environment
variables. No household endpoint can be used by this fixture profile.

Startup mounts local API state before discovery. The mounted screen restores
the durable journal independently of fixture, manifest and dispatch-worker
availability, placing an unresolved operation before setup controls. A missing
fixture cannot hide that fence. Preparation and confirmation still require the
separate execution capability; read-only recovery does not grant dispatch.

The screen first prepares a read-only review, then requests native preparation,
then presents separate confirmation. It supplies review IDs only. Session-owned
private requests retain both credential roles, native dataset commitments,
original simulator node bindings and the exact reviewed timing. Metadata
readiness never creates successful native preflight evidence.

`inspect` is a read-only worker mode. The session retains its immutable request
and native full binding for at most 30 seconds. Confirmation performs another
fresh native inspection, then the controller durably begins its global journal
fence. The adapter rereads that exact record before starting the dispatch child.
Only then does the child prepare and confirm its own same in-memory native
operation. The native guard rechecks snapshots after the source-only Petition
and immediately before one Pending SET. A changed/expired review cannot silently
be replaced during confirmation. Both source and target credentials travel only
through private memory and stdin, never argv or persistent fixture files.

The app route fixes propagation to 300 seconds and stable observation to 30
seconds. Other delays displayed by the older read-only planner do not enable
execution. Native and app operation IDs use 64 hexadecimal characters; the
previous lab worker retains its older 32-character compatibility.

## Fixture identity and lifetime

`tools/lab/commissioner/app_fixture.py` creates two source router processes and a
separate target process, establishes their empty-source inventory, and then
enforces the existing read-only simulator CLI whitelist. Its private Unix socket
supplies synthetic bootstrap credentials in memory and provisional discovery.
It writes only a nonsecret 0600 manifest inside a 0700 directory.

The manifest binds stable fixture/node identities to each original process's
Linux start ticks and current Border Agent port. The native worker checks process
birth and UDP socket inode ownership before authenticating; dispatch repeats
that identity check after preparation. Dynamic ports are excluded from stable
router commitments, so refreshed endpoints remain associated with the original
processes. A replaced process or an endpoint owned by a different process fails
closed. Names, discovered handles and matching network datasets do not establish
original-router identity.

Ownership covers the actual IPv6 `::1` destination used by DTLS. IPv4-only
ownership at the same port is insufficient. More than one applicable IPv6
socket inode is ambiguous and blocks, including a second process using socket
reuse options. A sole original-process IPv6 wildcard socket is supported only
inside the verified namespace containing exactly `lo`.

Each worker arms its independent 1000-second process deadline before parsing
input and holds an exclusive process lease until it exits. Dispatch writes and
syncs an operation/fence-time lifecycle receipt before native confirmation.
Standalone `observe` never petitions or sets: it must acquire the exclusive
lease and validate the operation's receipt before asserting worker termination.
Missing receipts or failed identity checks retain the journal fence. Parent
timeouts alone never assert death. The receipt is not an alternative to the
controller's journal and does not authorize retries.

The dispatch process exits before fresh standalone observation begins. Recovery
reacquires both credential roles and compares full source/target and original
router commitments to the private journal. New review/session generations do
not substitute new router bindings. An uncertain send cannot be cleared by
seeing the old source unchanged; definite rejection has its separate unchanged
observation path. No action replays a SET, deletes the journal, resets a router,
regenerates credentials or performs rollback.

## Offline software runtime

Enable native targets explicitly with `TNT_WITH_COMMISSIONER=ON`,
`TNT_BUILD_APP_MOVE_LAB=ON`, and `TNT_BUILD_MOVE_JOURNAL=ON`, using the verified
pinned Commissioner source. The new worker is `thread-network-move-app`; it is
not installed in the default application. The old frozen worker/image remain
independent reproduction evidence.

Inside the disposable isolated image, copy the Flutter project to a writable
tmpfs working directory, keep SDK/dependencies/native binaries read-only, and
run from that project:

```sh
python3 /opt/lab/app_fixture.py --scenario key-change-older-target \
  --runner /opt/runner/flutter test --no-pub --concurrency=1 \
  --reporter expanded test/isolated_move_runtime_test.dart
```

`lost-api-result` runs the same path while the native transport deliberately
discards the actual setter result. This tests API result loss, not packet loss.
The manifest explicitly binds that disposable test choice. It is unavailable in
default builds.

The supervisor launches two real Flutter test processes, setting `TNT_APP_PHASE`
to `dispatch` and then `recover` while preserving all three original simulator
processes. The first drives real role-bound dialogs, native reads, review and
confirmation, checks one Petition/SET and duplicate refusal, stops observation
and exits. The second restores the journal without dispatch, reacquires both
credentials and resumes fresh observation. The test waits real stack time,
requires full convergence/target-unchanged/connectivity from the independent CLI
oracle, and scans recovery files for synthetic secret material.

The fixture supplies the explicit socket, manifest, lifecycle and journal paths
and helper paths through `TNT_FIXTURE_*`/`TNT_MOVE_*`. Credentials are not
environment variables. The image must run with no external network, read-only
root, unprivileged UID, no devices/capabilities, private tmpfs and an outer
deadline. The fixture never bridges loopback to the Mac or a household network.

## Evidence and remaining gates

Local Mac verification: the new worker links from a fresh source-bound build;
38 native move cases and the focused commitment/lifecycle tests pass. A valid
fixture request refuses the unsupported Mac runtime before dispatch. Flutter
regression tests pass; the Linux-only runtime test is skipped on Mac. New bridge
sources analyze cleanly. These are build, guard and UI regression results,
not the actual isolated Linux app execution result.

Record the immutable source/build/image manifests and both isolated scenario
reports before claiming that app runtime acceptance passed. Vendor model and
firmware commands, physical stable identity, hidden/unsupported dataset fields,
accessory recovery, signing and distribution remain separate evidence gates.
Nothing in this slice establishes eero, HomePod, Nest or arbitrary router writes.
