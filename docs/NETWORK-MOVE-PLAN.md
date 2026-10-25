# Next implementation: source-network review

This brief follows the owner's first-release goal. The existing `join/` model
covers a vendor command for one router. A Pending Dataset update affects the
whole source Thread network and needs a separate plan and preview. The isolated
OpenThread lab is protocol evidence, not Eero, HomePod or Nest compatibility.

## Consumer workflow

Choose the network to keep, set up its access, then choose the source network
and set up separate access. Check the target router and every observed source
router. Show the source routers together and state that all devices on the
source network may be affected. Offline or unobserved devices remain unknown;
discovery is not a complete inventory.

The first supported case requires a controlled empty source, attested by an
operator who established its inventory. Missing advertisements and an empty
child table are insufficient. The preview shows propagation delay, interruption,
verification schedule and a demonstrated or explicitly manual recovery path.
No automatic factory reset, device removal, credential regeneration or replay
after an uncertain result is part of this workflow.

## Implementation slice

1. Replace the single live-session credential with in-memory source and target
   slots. Each import gets an opaque generation; never return the dataset, key,
   PSKc or private identity tuple in the public DTO or report. A role is explicit
   on imports and reads, with no silent target selection.
2. Retain authenticated network identity and Active Timestamp internally.
   Extend the read-only native probe's bounded metadata for dataset consistency
   checks. Keep discovery, authenticated identity and inventory distinct.
3. Add a pure `move/network_move_plan.dart` assessment. Require distinct source
   and target, fresh authenticated matching reads, empty pending state and
   consistent source timestamps. Block missing, stale or changed attestation.
4. Add a read-only plan API and live preview listing all observed source routers,
   blockers and unknowns. Bind the review snapshot to credential generations,
   discovery generation, selected handles, identities, read times, attestation
   and proposed timing. Re-import, re-discovery, changed evidence or expiry
   invalidates the snapshot.
5. Keep dispatch disabled until the actual adapter and device/firmware route
   have separate controlled validation. The planner adds no Petition or SET.

Expected files: `app/lib/native/session.dart`, `app/lib/live_api.dart`,
`app/lib/native_live_api.dart`, `app/tool/local_server.dart`,
`app/lib/live_screen.dart`, `native/probe.cpp`, the new pure planner, and
`docs/LIVE-READ-CONTRACT.md`. The guided setup dialog can receive a role-bound
callback without duplicating its credential handling.

## Countable acceptance

- Two distinct credentials remain associated with their explicit roles; there
  is no implicit target and wrong-role or same-network selection is blocked.
- Every observed source router appears in the preview; one mismatched, stale,
  pending or inconsistent source read blocks the plan. Target checks have the
  same freshness and pending-state requirements.
- Unknown offline devices and incomplete inventory remain visible. Missing,
  stale or changed controlled-empty-source attestation blocks readiness.
- Changed credential, discovery, read or timing evidence invalidates review.
- API results and reports omit secret datasets, keys, PSKc, private network
  identifiers and endpoints. Only local display has necessary household labels.
- All attempted mutation routes return unavailable/not found. Tests assert
  the native adapter calls only inspect, discover and probe.

Complete this read/review slice in a separate PR; do not present it as a working
network move. The subsequent adapter must reproduce the protocol lab through
the real Commissioner/Border Agent path and preserve the confirmed operation,
one-shot dispatch and observation/recovery rules.
