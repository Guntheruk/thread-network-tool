# Guarded native source-network move adapter — isolated validation

This implementation is an opt-in lab worker around reusable native C++ guards
and the pinned OpenThread Commissioner library. It is separate from the existing
application helper. The application CLI, installed payload and default
`network_writes: false` capability remain unchanged. No household, physical
router, vendor join command or accessory compatibility is established here.

## Authority and snapshots

`native/network_move.hpp/.cpp` owns a private copy of the source and target full
Active Dataset snapshots. It parses and validates complete TLV maps; comparison
includes Network Key, PSKc, Mesh Local Prefix, PAN ID, security policy, channel
mask, identity and full encoded Active Timestamp, not just public metadata.
Every observed source router and the target must authenticate and return an
exact matching full Active Dataset and an empty Pending Dataset. A hidden key,
partial read, changed byte, unsupported dataset field, duplicate TLV, existing
pending update or unavailable router blocks dispatch. Reads must finish within
30 seconds. Request roles and endpoint selections are immutable after prepare.

The request explicitly attests a controlled source containing no end devices
and acknowledges manual stop-and-observe recovery. Discovery and child-table
absence do not establish this inventory. This lab constructs exactly two source
router-capable nodes and one separate target node before making that attestation.

Prepare returns an opaque in-process confirmation token. Confirm consumes the
operation once under a native operation/dispatch mutex, re-reads every snapshot,
requires a nonsecret unresolved-operation fence, petitions only the selected
source router, and rechecks every snapshot before the single Pending SET call.
The review expires after 30 seconds. The fence denies any existing unresolved
operation, including one with a different operation ID. The lab uses a fixed
owner-only exclusive file in its private `/tmp`; file and directory are synced.
It never clears that fence automatically. A future application worker must also
have its caller's durable global fence established **before child launch**;
this lab-local fence is not that production journal.

A native mutex does not lock a distributed Thread network. MeshCoP supplies no
compare-and-set of the complete Active Dataset here. Another administrator could
change state between the last GET and SET. The controlled isolated fixture has
no competing writer; this implementation does not claim to close that protocol
race for arbitrary networks.

## Timestamp and dataset rules from the exact pins

Pinned OpenThread `53e8322140dde7b26827332100504507cec9cc4e`,
`src/core/meshcop/dataset_manager_ftd.cpp::ProcessSetOrReplaceRequest`, requires a
new Pending Timestamp. Without a Network Key change it also requires the proposed
Active Timestamp to be newer than the source Active Timestamp. With a different
key, an older or equal Active Timestamp is permitted. In
`dataset_manager.cpp::HandleDelayTimer`, activation independently requires a
newer Active Timestamp **or a different Network Key**.

The adapter retains the target's original Active Dataset and timestamp exactly.
It never bumps the target timestamp to make migration pass. Same-key transfers
to an older/equal timestamp block. Pending Timestamp is independently constructed
at one second above the larger source/target seconds value; overflow or the
reserved invalid timestamp blocks. Capacity includes the added Pending
Timestamp, Delay Timer and Commissioner Session ID TLVs.

The exact stack defaults clamp key changes to at least 300000 ms; other changes
have a 30000 ms minimum. This profile accepts 30000–600000 ms subject to those
constraints. The lab does not lower the stack defaults or speed up time.

The pinned Commissioner `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae` provides
`GetRawActiveDataset` but no raw Pending Dataset setter. Its typed encoder
represents ten Active Dataset TLVs. This adapter therefore explicitly reports
`unsupported_dataset_fields` for any source/target field it cannot reproduce,
including Wakeup Channel TLV 74. It retains unknown raw TLVs for comparison and
never silently drops them or lets source-only fields carry over. This is a
**temporary pinned-adapter capability limit**, not a declaration that TLV 74 is
invalid. A separately reviewed Commissioner extension is required before those
real datasets can use this route.

## Outcomes and observation

A submission report has `schema_version`, validated opaque `operation_id`,
`disposition`, a fixed `reason`, and bounded Petition/SET invocation counters:

| Disposition | Meaning |
| --- | --- |
| `proven_not_sent` | This native operation did not invoke Pending SET. A source Petition may have occurred. |
| `accepted` | The Pending SET response explicitly accepted this request; convergence remains separate. |
| `rejected` | The Pending SET response explicitly rejected this request. |
| `uncertain` | Pending SET was invoked and completion is unknown. An exception after invocation cannot become safe failure. |

One application invocation is one logical CoAP exchange; transport retransmission
may occur. No claim of one UDP packet is made. A timeout, lost worker output,
crash or generic launch/worker error must be treated as uncertain by a caller
unless it receives and validates matching explicit native proof. A different
operation ID is not permission to retry an unresolved move. Root's execution
controller/journal work remains separate from this lab worker.

The worker has an independent 1000-second process alarm; its lab driver has a
1000-second deadline and Docker an outer 1100-second timeout plus 5-second kill
allowance. Parent wait timeout alone does not prove child termination. EOF after
confirmation or a generic exception yields uncertain; no automatic SET replay,
factory reset, deletion, key regeneration or rollback is provided.

`ObservePending` verifies the exact target fields, Pending Timestamp and bounded
remaining delay on **both** source routers, while the target remains unchanged.
`Observe` discards cached sessions, takes explicitly refreshed source and target
endpoints and authenticates with target
credentials, requiring full target Active Datasets, empty Pending state and an
unchanged target. It rejects duplicate or cross-role endpoint tuples and never
petitions or sets. Endpoint authentication proves network membership; identifying
the original physical routers across endpoint refresh is the caller's responsibility.
The lab binds that correlation to the exact simulator processes. Border Agent UDP ports may change
at activation; a refreshed endpoint remains untrusted until authentication.

## Lab entry and isolation

`thread-network-move-lab` is built only with `TNT_BUILD_MOVE_LAB=ON` and
`TNT_WITH_COMMISSIONER=ON`; it is not installed or added to the application CLI.
Its entry rejects every endpoint except literal `::1` and `127.0.0.1`, before
constructing the network adapter. The reusable C++ module does not impose this
lab-only endpoint restriction on a future validated worker.

Stdin uses a strict fixed-order `TNT-MOVE/1` frame: operation ID; source and target
hex datasets; source count and source endpoints; target endpoint; delay;
controlled-empty attestation; manual-recovery choice; `END`. Maximum input is
16384 bytes, line length is bounded, dataset hex is at most 508 characters,
source count is 1–8, numeric ports/delay are bounded. Credentials have no argv
option. Review/confirmation and subsequent pending/observation commands stay
in the same process. JSON reports omit datasets, keys, PSKc, endpoints, labels
and raw upstream errors. Lab diagnostics are fixed phase names and integer
library error codes only.

`move_driver.py` creates the networks before launching the worker. It then
switches its simulator CLI wrapper to an enforced read-only whitelist: dataset
GETs, state, partition, Border Agent port, mesh-local address and ping. There is
no simulator CLI dataset write available after setup. Thus the tested mutation
must come from the reusable guarded module through the real Commissioner
`SetPendingDataset` and Border Agent, rather than CLI `mgmtsetcommand`.

All three nodes are POSIX Border Agents with simulated RCPs on loopback; no TUN,
physical radio, OTBR service, host device, infrastructure forwarding or mDNS is
needed. `Dockerfile.move` builds from the verified Stage 1 timestamp image and
checks an independent `move-source.sha256` manifest. Preserve the Stage 1
context/manifest and use a fresh task-owned move context.

```sh
docker build --network none -f /tmp/tnt-network-move-lab-20261025/Dockerfile.move \
  -t tnt-network-move-lab:20261025 /tmp/tnt-network-move-lab-20261025
timeout --signal=TERM --kill-after=5s 1100s \
  docker run --rm --name tnt-network-move-keychange-20261025 \
  --network none --read-only --tmpfs /tmp:mode=1777 \
  --user 65534:65534 --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 64 --memory 1g --cpus 2 \
  --env TNT_MOVE_SCENARIO=key-change-older-target \
  tnt-network-move-lab:20261025
```

Other scenario values are `same-key-newer-target` (30-second minimum) and
`lost-api-result` (same-key/newer-target, intentionally discards the real setter
return value). The latter tests API-result loss, **not wire packet loss**.
Use a fresh container/tmpfs for each disposable fixture. A prior uncertain
household operation could never be retried this way.

## Verification record

- Existing system clang++ compiled the pure guard tests with `-std=c++17 -Wall
  -Wextra -Werror`; 35 counted cases passed. The Linux Docker build also passed
  the native move CTest. No Mac SDK/package was installed.
- Four Python driver tests pass: full TLV-map comparison, enforced read-only CLI
  oracle, public report redaction, and explicit uncertainty after submit timeout.
- The first key-change runtime formed both source routers and passed real
  loopback/stdin rejection checks, but timed out waiting for a terminal native
  submission response at 45 seconds. Its absent disposition is uncertain, not
  proven-not-sent. Image was
  `sha256:cdfc481702303d8f1f70f3cbe40dd8168665a1be8e199aaf33c2e9db80deca95`.
- A diagnostic same-key fixture stopped before worker launch because role
  readiness did not establish source partition agreement before its initial assertion.
  Setup now explicitly waits for that agreement. The specific mismatch was not
  captured; no migration pass is claimed from that attempt.
- A diagnostic trace reached `set_result:0` but the old adapter queued an async
  Disconnect immediately before CommissionerSafe destruction and did not return.
  The pinned one-item invocation queue can coalesce those notifications. Direct
  destruction after the synchronous result removed this caller lifecycle issue.
- An intermediate accepted key-change run physically converged after 300 seconds,
  and a lost-result run physically converged after 30 seconds, but their cached
  read sessions returned invalid-state 15 during final native verification. They
  failed closed. Observation now discards old sessions and authenticates fresh,
  with explicitly refreshed source and target endpoints. The final runs below
  exercise that correction.

A running first-container inspection confirmed `network=none`, read-only root,
UID/GID 65534, dropped ALL capabilities, privileged false, no binds/devices/ports,
only `/tmp` tmpfs, PIDs 64, memory 1073741824, CPU quota 2000000000 and
`no-new-privileges`. This is isolated runtime evidence, not household support.


## Final frozen evidence — 25 October 2026

All three final independent containers exited 0 with all **16** checks true:

| Scenario | Delay | Dispatch disposition | Final verification |
| --- | ---: | --- | --- |
| Different key, source timestamp 20 → target 10 | 300000 ms | accepted | Complete |
| Same key, source timestamp 20 → target 30 | 30000 ms | accepted | Complete |
| Same key/newer target, real setter result deliberately discarded | 30000 ms | uncertain | Complete by observation; no second SET |

For each: real source-only Petition and one native Pending SET invocation;
authenticated complete Pending Dataset propagation on both source routers;
exact full target Active Datasets after activation; source router/leader roles;
a shared partition with the target; bounded mesh-local ping; and fresh native
DTLS/full-dataset observation. Target Active Dataset and Pending state remained
unchanged. “Target unchanged” refers to these datasets; partition/leader roles
can change normally as Thread partitions merge.

Mutation was performed by the guarded native module through the real
Commissioner/Border Agent path. After setup, the CLI oracle's enforced whitelist
prevented it from issuing any dataset write. CLI observations independently
checked the actual two original source simulator processes. This distinguishes
a working guarded adapter from the older CLI `mgmtsetcommand` simulation.

The frozen image is
`sha256:d06ee88cce40159e84fc2041f835c6743c4333be95abe064c8626a53cf26de99`.
Source is the uncommitted Stage 2 slice based on
`242ba69a085d25b1bb9a4a04187c21553d32dd63`, pinned by the checked full input
manifest rather than a claim that this base Git commit contained the new code.

- Move driver SHA-256: `ed11248d03c6386a3ec161ab4cbc98be1c88283cc0db38b35549f6d1bd230f9c`.
- Move Dockerfile SHA-256: `917dcaf1dbb6e26592945fe8da6cb7e6e9454b319ce259419ba9639bed48e999`.
- Move source manifest SHA-256: `fcee2c3325f5b46969c6e418a618e434bfbb68dead3c64149e557feb957a0085`.

`tools/lab/commissioner/move-evidence-20261025.json` records the exact allowlisted
reports, pins, hashes and isolation limits. Runtime commands used the command
above with the immutable image ID, the respective scenario, and unique names
`tnt-network-move-final-keychange-20261025`,
`tnt-network-move-final-samekey-20261025` and
`tnt-network-move-final-lostresult-20261025`.

Default-gate verification used `Dockerfile.default-check`, a verification-only
derivative of that exact image. Its default OFF build passed all four native
CTests, produced no move worker, and reported `network_writes: false`. The derived
image is `sha256:227493dff8c1e4734b3c00ef40a8b16c22710aea3e756d9c27a261951d44f0b3`.
An earlier attempt compiled in runtime `/tmp` but execution was correctly denied
by its noexec mount; execution was moved to the offline build stage without
changing runtime privileges or mount options.

The source-only dataset operation is proven for this controlled simulator
profile. Physical/vendor support, legacy TLV 74 support, application journal/UI
dispatch integration and production packaging remain separate gates.

Exact-name inspection after the final runs returned no owned runtime containers.
The cached images and task-owned Linux build context remain for reproduction.
