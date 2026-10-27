# First-release completion plan

Owner direction, 25 October 2026: keep building toward a usable application,
use focused agents and PR review, and take the supplied product strategy into
account. A working window is a milestone, not completion.

Credential routes and the optional phone companion are distinguished in
`CREDENTIAL-ACCESS.md`. Existing authorized credentials can avoid a new phone
app. The owner's suggestion of a useful mobile product remains an open
possibility; a companion is not required for every desktop user.

## Product acceptance

- A person can discover routers and set up access without understanding hex:
  guided eero copying works, raw import is under Advanced, and supported saved-
  credential providers use explicit consent and clear unavailable/error states.
- Credentials are validated before use. Discovery, credential access, router
  authentication, a proposed join, command acceptance and verified outcome remain
  distinct. A preferred network is never silently assumed to be the user's target.
- A supported join has a model/firmware-specific command, confirmed source and
  target, fresh checks, a concrete preview, explicit confirmation, and a tested
  observation/recovery path. An uncertain command is never blindly retried.
- Source networks with existing accessories are outside the first supported join
  case unless a separately tested migration route exists. Empty/new source status
  requires controlled evidence; discovery silence does not prove emptiness.
- The app runs locally without a required account, Home Assistant or AI. Optional
  vendor account authorization must serve that provider's actual feature.
- Reports use a small allowlist, are previewed locally, and contain no credentials,
  household labels, endpoints, device identities or persistent installation IDs.
  Copying a report does not enroll anyone in telemetry, marketing or research.
- Platform support is stated per capability and actual build/runtime evidence.
  Generated project files and a shared UI do not establish Windows/phone support.
- The exact candidate passes meaningful tests, independent review, native runtime
  checks and dependency-notice review. External distribution gates are recorded.

## Execution order

| Lane | Deliverable | Acceptance evidence |
| --- | --- | --- |
| Consumer setup | Guided eero and Advanced routes, clear failures, accessible narrow layouts | Widget tests and actual Mac/web flow |
| Apple access | Read-only native bridge, consent only on explicit request, bounded typed results | Mocked failure/timeout tests, Swift compile, packaged preflight; real access only when signing/entitlement is available |
| Join assessment and recovery | Portable state model, evidence rules and isolated lab harness | Stale/ambiguous/duplicate/restart/mismatch tests; no real mutation in synthetic harness |
| Protocol lab | A controlled supported router route with real verification | Isolated hardware or software evidence appropriate to the exact operation; no household experiment |
| Platform/providers | Android credential bridge and verified Google/device capabilities; Windows transport/build path | Per-platform builds and supported-device runtime checks, with unsupported cases explicit |
| Privacy and release inputs | Local report preview, deterministic third-party notice inventory, compatibility matrix | Redaction tests, notice collection, exact-version evidence |
| Candidate review | Focused PRs and native app verification | Reviewed source head, local results, separate hosted CI result |

## How the supplied strategy is used

The useful direction is a focused local utility with understandable setup,
specific compatibility evidence, recovery and a small varied pilot. General
Thread credential sharing and network migration are prior art; no novelty or
universal compatibility claim follows from a successful case.

The report's licence suggestion, public-source release, telemetry uploads,
email/research signup and commercial model are proposals, not automatically
accepted requirements. Do not add accounts, analytics or collection services to
finish this build. Preserve licence choice and public distribution as owner
decisions after dependency review. Signing/notarization and Apple/Google access
approvals are external gates, not substitutes for implementation.

## Current boundaries

The active goal must not be marked complete merely because a milestone passes.
Record implemented, tested, reviewed, hardware-verified and external-blocked work
separately in PROGRESS.md. Keep working on independent items when one lane needs
an external approval or test device.

No household router migration, reset, credential regeneration or working-device
change is authorized by this build plan. Real-network mutation requires a concrete
reviewable operation and the appropriate owner authorization. Public release,
purchases, account changes and telemetry collection are separate actions.
