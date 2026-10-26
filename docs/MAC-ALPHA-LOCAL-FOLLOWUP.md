# Mac alpha local follow-up — 26 October 2026

The production app remains code version `7422ddc8a3b14dec75acb2a005c59198b39d3bc9`.
The follow-up at `220bf755a833666b1b1f833c9e46353816a09c34` changes acceptance
tests and tester documentation only; it does not change application binaries.
The updated ZIP retains the exact previously accepted signed app.

## Screen and recovery acceptance

The added widget test connects the production NetworkMoveScreen, NativeLiveApi,
LiveSession, MacMoveAdapter and real native journal. It proves preparation grants
no durable send authority, explicit confirmation dispatches once, and rebuilding
the screen/session/adapter restores the unresolved operation without credentials,
a confirmation control or automatic checks. After synthetic credential reimport
and discovery, manual recovery adds one observation and no second dispatch.
All three tests in `mac_move_session_integration_test.dart` passed with the native
journal configured and no skips; Flutter analysis found no issues. Independent
review of `9ff6dba..220bf75` found no actionable issue.

The worker process and read replies remain synthetic. Reconstructing objects is
not a packaged-process restart; this test does not advance the real five-minute
transition or replace the existing native wire and signed-parent evidence.
Production loopback restrictions were preserved.

## Relocation and translated helper checks

The original ZIP SHA-256 is
`897d7fe6d6a34312205878e0cbb72b509dc91c90ff0a936383e9ced2102c0f3b`.
It was unpacked into a fresh temporary directory. Recursive strict signature
verification passed. Process inspection confirmed the native Flutter window ran
from that unpacked app, showing the alpha join route, zero routers and search not
yet run. No discovery, router check or household credential import was invoked.
This is relocation on the development Mac, not clean-Mac installation proof.

A disposable signed sandbox parent with only the app-sandbox entitlement launched
the unchanged packaged parser and join worker with x86_64 explicitly selected via
posix_spawnattr_setbinpref_np. Under existing Rosetta, worker capabilities and
valid/invalid synthetic parser inspections passed. The three component hashes
matched the production package:

- `thread-network`: `a33ca8f8e1b837b1b13a20937d7b234453c280672f8e30b8ddbe59cdd93d94b5`
- `tnt-mac-move-worker`: `de042a90660a210c88e6a70b9e6e109b6e19cf0cfb59aa5c5f82001f29103520`
- `libthread_network_core.dylib`: `2818fcbcc02847e83e13e89bb643d92a11f6cec75ba6868a2cc11744829f079f`

The enclosing Codex process sandbox initially aborted the test parent before
main; the documented normal execution context passed without relaxing the app's
sandbox or signatures. No network entitlement or network command was used in
these helper checks. This does not verify the journal or Flutter app in Intel
mode, or execution on physical Intel hardware.

## Remaining isolated migration failure

One fresh diagnostic run of frozen `787ace4d43d2317744238d172d94e0b892b89677`
used image `sha256:5a8f1acb35081de5188db0eebebd8e3c2b315dd9b42cf19f9c7a664401e356e9`.
After 511.3 seconds and 167 fresh observations, all six configuration checks
passed, while independent connectivity remained false. The app ended at
`needs_attention / verification_failed / oracle_incomplete`.

Failed ping frames contained the command echo and completion marker, no reply,
and explicit 100% loss. Original target to moved peer also failed; moved peer to
moved source passed. This excludes discarded ping replies as the immediate
explanation and localizes the failure to communication across the original
network boundary in this simulator. Routing, key-sequence or address state has
not been distinguished; there is no evidence-backed application repair yet.
The strict connectivity check was preserved.

This was a disposable software fixture with no external network, host binds,
ports or devices, a read-only root and unprivileged user. The container was
removed and its absence confirmed. No retail Eero compatibility follows.
Sanitized summary SHA-256:
`70985b5785d05dff11d2ea0b0f2c43e8c81901e90b33507b6fe373b254a6afec`.
The reproducible local evidence is retained under
`/tmp/tnt-keychange-diagnostic-20261026`; its runner is a review pointer, not an
automatic retry. The local app ZIP includes a bounded summary, not raw logs.

## Remaining distribution boundaries

The build Mac still has no valid Developer ID signing identity. Trusted signing,
notarization, clean-Mac installation, physical Intel execution, controlled retail
Eero migration/recovery and the owner's licence/distribution decision remain
open. The working household was excluded throughout. No push, hosted check,
cloud review or publication was performed.
