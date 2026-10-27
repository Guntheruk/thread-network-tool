# Mac Eero alpha

## Scope

Owner direction on 26 October 2026: finish a real Mac Eero joining flow using
manual credentials, including guided eero copying and optional import from an
existing Home Assistant. Leave the household routers and working accessories
alone during development. Native Apple credential retrieval, phone companions,
Windows networking, Google Home commands and accessory transfer are outside
this alpha.

This operation changes the **whole source Thread network**, not one Eero.
The person confirms the source is their Eero Thread network, every source Eero
is represented, and no accessories use that source network. Discovery cannot
prove that inventory or manufacturer identity. The target network receives
reads only. Existing source accessories are not migrated by this workflow.

Both complete datasets are needed. The eero app supplies its Active operational
dataset. The network being kept can be imported from an existing authorized
Home Assistant or Advanced input. The alpha cannot retrieve otherwise
unavailable Apple credentials, and Home Assistant is not a core dependency.

## Implemented path

The production Flutter entrypoint discovers routers only on request. Its
separate join review binds source/target credentials and exact numeric endpoints,
requires the confirmations above, authenticates complete Active/Pending reads,
and offers a short-lived final confirmation.

The opt-in `tnt-mac-move-worker` accepts private requests through stdin, never
credentials in argv. It supports 1–8 pinned source endpoints and one target,
private IPv4 or IPv6 ULA addresses, and a 300–600 second native delay. The app
currently selects 300 seconds. IPv6 link-local scope identifiers and endpoint
rebinding are unsupported. Changed/missing endpoints require attention rather
than being guessed from a network name.

The worker checks the matching durable journal, writes a durable no-replay
receipt, petitions only the source, rereads every snapshot and invokes one
Pending Dataset SET through that source. Transport retransmissions can occur;
one invocation does not mean one UDP packet. A lost response remains uncertain.
No retry, reset, credential regeneration or automatic rollback is implemented.

After explicit confirmation, the foreground Mac screen waits for the propagation
delay and automatically runs serialized read-only checks. Checks stop at a final
result, after a bounded two-minute window, or when the user stops, leaves the
screen or backgrounds the app. An in-flight bounded read can finish, but cannot
dispatch another change. Reopening the app leaves recovery checks manual.

The journal and lifecycle lease live inside the app's private Application Support
directory. Restart restores the unresolved operation and cannot reconstruct a
send authorization. Credentials are not persisted; recovery needs the same
credentials and the original endpoint bindings again.

Mac completion is `verified_configuration`: all original source endpoints
repeatedly authenticate with the complete target dataset, have empty Pending
state, and the target remains unchanged over a fresh stable interval after the
delay. It does not claim RF coverage, a measured Thread data path, physical
router identity, accessory reachability or seamless accessory migration. The
separate software-lab profile still requires its independent connectivity check.

## Building

`tools/build_macos_app.sh` remains read-only by default. An actual alpha package
requires `TNT_MAC_ALPHA=1`, which builds and bundles the Mac move worker and
journal. It validates the worker's capabilities and signs both helpers with
sandbox inheritance before signing the outer app. Disposable fixtures and Linux
lab workers are excluded, including when reusing a prior CMake cache.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TNT_MAC_ALPHA=1 \
TNT_FLUTTER_BIN=/absolute/path/to/flutter/bin/flutter \
TNT_CMAKE_BIN=/absolute/path/to/cmake \
TNT_COMMISSIONER_SOURCE=/absolute/path/to/verified/commissioner-source \
TNT_NATIVE_BUILD_DIR=/absolute/path/to/fresh/native-build \
TNT_OUTPUT_DIR=/absolute/path/to/new/package \
tools/build_macos_app.sh
```

Local signing is ad hoc. The packaging script also supports an already-installed
Developer ID identity; notarization, distribution approval and clean-machine
installation are separate, unfinished release checks. No purchase or account
change is part of the build.

## Evidence and limits

- Local Mac session tests exercise review, explicit attestation, the real native
  journal, one fake-process dispatch and restart recovery without replay.
- Native wire tests use the actual Commissioner worker against synthetic,
  loopback-only DTLS peers. They cover full reads, source-only Petition/SET,
  target read-only behavior, rejection, lost response and no replay.
- Signed-parent scripts exercise the bundled inherited helpers from a Flutter
  app sandbox. Their entrypoints are separate from production and require
  `TNT_TEST_PACKAGE=1`; they are not consumer applications.
- The historical household Eero move used an earlier standalone helper. It is
  protocol evidence, not a test of this packaged app. No household migration
  was performed while implementing this alpha.
- The older isolated Linux app scenario at `787ace4` still failed its independent
  post-move connectivity check despite matching datasets, empty pending state,
  shared partition and router roles. A separate same-network diagnostic proved
  that the CLI ping reply arrives before `Done`; framing is not an established
  explanation for that failure. The lab check has not been weakened.

The production package at `7422ddc8a3b14dec75acb2a005c59198b39d3bc9` passed its
local window acceptance and includes the same worker/journal bytes tested in the
signed loopback suite. See [the exact acceptance record](MAC-ALPHA-ACCEPTANCE.md).

Before a broader alpha release: controlled Eero model/firmware acceptance,
trusted distribution and clean-Mac installation, and the owner's
license/distribution decision remain. The owner has no spare Eero available;
an existing Eero is not an isolated source because this operation applies to its
whole Thread network. No household move is authorized to fill that evidence gap. Do not
present synthetic peers as retail Eero support or a locally signed build as a
notarized release.
