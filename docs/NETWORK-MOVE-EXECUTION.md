# Bounded whole-network execution

This contract extends the read-only review at source
`38ea9baaeff58a4c6817ff4e3247ab05b23a64e2`. It does not relabel the existing
single-router `join/` model as a whole-network operation. The first possible
execution profile is `openthread-posix-lab-v1`: an isolated OpenThread route with
a controlled source containing routers and no accessories. Neither a protocol
simulation nor a successful read establishes eero, HomePod, Nest, or other
vendor compatibility.

The execution controller and journal are implemented separately from the screen,
live-session preparation, actual Commissioner worker, and packaging. Until those
parts are connected and their exact runtime is verified, this is execution
infrastructure with an injected worker, not a working native app move.

## Authority and data boundary

The UI confirms a specific reviewed operation. The trusted session resolves its
review ID to an immutable `MoveExecutionPlan`; clients must not submit their own
plan, compatibility flags, endpoint, dataset, or read-success claims. Beta opt-in
and credential import are not confirmation.

The private native request must bind:

- Source and target credential generations, session/discovery/connectivity
  generations, the complete source router set, exact selected target, and the
  tested stable router identity bindings.
- Full canonical source and target datasets, permitted TLVs, timestamps,
  authenticated fresh reads, empty pending state, controlled inventory evidence,
  timing, and exact model/firmware/runtime capability profile.
- The selected source-only dispatch endpoint and the retained target endpoint.

`bindingCommitment` is a native-produced commitment to this complete reviewed
snapshot, not a hash of just a display name or public metadata. Source/target
commitments compare complete canonical operational datasets. Router commitments
must derive from the profile's demonstrated stable identity binding, not a fresh
discovery handle. The commitments are private household metadata, not exported
diagnostics. They must never be raw credential bytes padded to fit the schema.

The current public read metadata does not establish this full binding. The
integration must add actual native comparisons and identity evidence; it must not
fill in a successful preflight using `readyForLabReview` or guessed flags.

The controller supports only the named isolated profile and requires trusted
preflight evidence for profile verification, the actual runtime, and an
independent worker deadline. A native-only adapter must perform another full
comparison after its source-only Petition, immediately before its one Pending
Dataset SET. Any mismatch blocks that SET. Unknown/hidden/unsupported dataset
fields block execution instead of being dropped by a typed setter.

## API and state

`MoveExecutionController` provides:

| Method | Effect |
| --- | --- |
| `confirmAndStart(plan)` | Revalidate the trusted plan, obtain durable fence, invoke worker once. |
| `current()` | Initialize recovery if needed, then read authoritative private status. |
| `restore()` | Convert an unresolved fence to uncertain recovery; clear prior observation continuity. Never invokes worker. |
| `checkOutcome(id, resume: false)` | Fresh read-only observation; explicit `resume: true` restarts stopped observation. |
| `stopObservation(id)` | Stop observation, retain the global fence, invalidate late callbacks. |

The persisted stages are `dispatch_fenced`, `observing`, `needs_attention`,
`observation_stopped`, `verified_complete`, `verified_unchanged`, and
`proven_not_sent`. The latter three are terminal. There is no automatic retry,
rollback, credential regeneration, factory reset, accessory deletion, or replay
on restart.

Worker results correlate the exact operation ID and distinguish
`proven_not_sent`, `accepted`, `rejected`, and `uncertain`. Accepted means command
acceptance only. A mismatched ID, unknown disposition, exception, or generic
post-fence launch failure is uncertain. A journal update failure after the worker
leaves the durable fence in place and returns `journal_after_dispatch_uncertain`.
The caller must read recovery state; it must not offer a button that resends.

One SET means one native setter invocation/logical exchange. Any CoAP transport
retransmissions must be audited separately; this contract does not claim one UDP
datagram.

## Native durable journal

`native/move_journal.*` and `move_journal_cli.cpp` implement a narrow, bounded
local line protocol. `NativeMoveJournal` invokes it without a shell. Credentials
are never sent to this helper. The journal contains operation/profile/revision,
state/disposition, private source/target/router commitments, observation timing,
and fixed reason codes. It accepts no arbitrary JSON, endpoints, labels, raw
datasets, raw logs, or credential fields.

The app provides one canonical journal directory in its private application
support location. Its parent must exist. `initialize` creates only the final
directory, with owner-only mode 0700. Files are owner-only mode 0600. Final-path
symlinks, wrong owner/mode, nonregular files, hard links, malformed records and
unknown fields fail closed. The helper validates the directory before creating a
lock file. An exclusive nonblocking `flock` serializes processes; updates use
compare-and-swap revisions and preserve immutable operation bindings.

Before worker launch, `begin` writes a permanent random operation-ID marker and
flushes it, writes and flushes the new record, atomically renames it, and flushes
the directory. macOS additionally uses `F_FULLFSYNC` on regular files. The parent
directory is flushed so a newly initialized journal directory is not merely an
unflushed name. A failure or lost acknowledgement at any step prevents launch.
A crash can therefore leave an unnecessary fence, but cannot authorize replay.
Markers prevent reuse after a later terminal operation replaces the status
record. There is no journal reset/erase API.

The global unresolved-operation fence intentionally blocks other sources too.
This avoids needing a persistent household identity index to prevent retries
under rediscovery aliases or another operation ID. `proven_not_sent` and verified
terminal outcomes permit a new separately reviewed operation, not replay of the
old ID. Terminal records and immutable bindings cannot be rewritten.

This implementation uses actual POSIX primitives, not a claim that Dart
`RandomAccessFile.flush` plus rename makes a durable transaction. Mac filesystem
and process-restart tests have run. Linux code is implemented but its application
write runtime still needs separate verification. Windows journal/writes are
explicitly unsupported. Filesystem/process tests do not simulate physical power
loss or prove storage hardware flush behavior.

## Observation and recovery

Every controller entry point performs shared one-time recovery initialization
before consuming journal state. An unfamiliar operation first appearing after
initialization receives the same recovery treatment. An inherited unresolved record loses persisted
observation continuity even when the caller starts with `current()` or
`checkOutcome()` and never calls `restore()`. Initialization uses the journal's
revision check and fails closed on a conflict or persistence failure. Concurrent
callers share an in-flight initialization or unfamiliar-operation recovery.
Failed attempts are evicted so a later call can retry after transient journal
contention; successful recovery remains cached and polling retains continuity.
A retry performs recovery reads and journal updates only, never worker dispatch.
Operations
started by that controller and repeated status polls retain their current
observation interval. Explicit `restore()` still breaks continuity; constructing
a new controller conservatively starts a new recovery interval.

After restart, credentials must be reacquired and matched to the saved private
commitments. The profile must re-establish the original router bindings; a new
discovery handle or matching name is insufficient. If this cannot be established,
return a recovery binding failure and retain the fence.

`MoveObservation` comes only from the trusted read adapter. Completion requires
all retained source routers, exactly one bound target, authenticated reads of the
expected complete datasets, empty pending state, demonstrated connectivity,
fresh samples after dispatch, and confirmed worker termination. A parent-side
timeout is not proof that the native worker is dead. The worker must enforce its
own deadline when the parent exits, and the adapter must establish termination
before releasing the fence.

The controller requires matching samples spanning the profile's observation
interval and at least the reviewed propagation/observation time. The earliest
source/target sample must itself reach the reviewed deadline: a read sampled
before the deadline and returned afterward remains pending until fresh samples
reach it. Samples older
than 30 seconds, a gap exceeding 30 seconds, a mismatch, an app restart, or an
explicit observation stop break continuity. A single read after a long sleep
cannot establish a successful observation period. Status updates use revisions,
so a late callback cannot undo a newer stop.

For `accepted` or `uncertain`, completion requires every source to match the
reviewed target and the retained target to remain unchanged. Seeing the original
source unchanged does **not** clear an uncertain fence: an accepted delayed
update could still apply. Uncertain nonconvergence remains needs-attention and
may require the profile's manual recovery procedure; there is no automatic
retry/release shortcut.

For a native **definite rejection only**, `verified_unchanged` is available after
the worker is confirmed terminated, every source freshly matches its exact
original full dataset with no pending update, and the target remains exact and
pending-free over the stable observation interval. This is a verified failed
move, not successful migration. The tombstone remains, and another attempt needs
a new explicit review/confirmation. Missing/stale routers, pending updates,
changed target, or a live worker retain the fence.

The controlled empty-source profile makes no claim about accessory recovery.
Adding accessories or unverified vendor hardware is a different capability
profile and test program.

## Verification and remaining integration gates

`tests/tools/test_move_journal.py` uses real native helper processes/files:
private modes, process contention, immutable bindings/revision conflicts,
corruption, symlinks, ID replay, and exits after file sync, rename, and directory
sync. The fault hooks exist only in a separate test executable.

`app/tool/move_execution_test.dart` uses the real helper with an injected worker:
duplicate confirmation, capability/freshness/binding failures, fence failures,
uncertain worker outcomes, rejected recovery, complete source/target evidence,
observation continuity, stop/late-callback races, and separate Dart process exits
before/after an injected worker call. Separate seed/recovery Dart processes
also verify that accepted, uncertain, and definitely rejected operations cannot
reuse a pre-exit stable interval through either `current()` or direct
`checkOutcome()`: each requires a full fresh interval without worker replay.
These prove controller/storage behavior;
they are not native Commissioner or vendor runtime evidence.

| Original acceptance gate | Evidence in this slice / remaining work |
| --- | --- |
| 1. Two-source native move, one SET, unchanged target | Commissioner lab lane; not claimed here. |
| 2. Same route through actual native app UI | Session/worker/screen/package integration pending. |
| 3. Honest exact capability gates | Controller checks tested profile/runtime/deadline; adapter must supply real evidence. |
| 4. Complete immutable reviewed binding | Controller compares commitment; full native/session construction pending. |
| 5. Missing/stale/mismatch/pending/inventory blocks | Existing assessment plus native preflight integration; controller rejects blockers. |
| 6. Duplicate and cross-process prevention | Real journal process tests and controller tests. |
| 7. Journal failure before launch | Fail-closed journal and controller tests; no unsupported durability fallback. |
| 8. Crash/restart boundaries | Real subprocess exits and native durability-boundary fault tests. |
| 9. Client disconnect with actual native worker | Dispatch fence proven; real worker/UI disconnect integration pending. |
| 10. Lost response/timeout/invalid result | Typed controller uncertainty tests; actual transport fault injection pending. |
| 11. Observation, incomplete outcome, stop races | Controller tests with real journal and injected read evidence. |
| 12. Consumer UI and private reports | Journal allowlist tested; actual screen layout/copy and unchanged report allowlist require integration checks. |

Build the helper with C++17 from `native/move_journal.cpp` and
`native/move_journal_cli.cpp`. Build the fault test executable from the same
module and `tests/native/move_journal_fault.cpp`. Set `TNT_JOURNAL_CLI` and
`TNT_JOURNAL_FAULT` when running the Python test. Pass the helper executable to
the standalone Dart test. CMake, app bundle placement, helper signing, and the
actual adapter are integration responsibilities; callers inject helper and
journal paths rather than assuming development paths.

This work adds no account, Home Assistant dependency, AI service, telemetry,
licence choice, or household operation.
