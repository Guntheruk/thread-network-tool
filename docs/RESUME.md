# Mac alpha continuation — 26 October 2026

The owner resumed work and explicitly requested the actual Mac Eero join flow,
using guided/manual or existing Home Assistant credentials. The earlier account
switch pause below is historical and revoked. Do not resume the separate Mac
internal-radio or household sensor maintenance scope as part of this app build.

Current integration checkout: `/Users/richard/thread-alpha-worktrees/integration`,
branch `feat/mac-eero-alpha`, based on clean `21c45b1`; the original
`/Users/richard/thread` candidate is preserved. Read `MAC-ALPHA.md`, current
PROGRESS and the newest Git commits before work. Root owns Git. Temporary older
`/tmp` worktrees disappeared; current work and evidence use persistent paths.

The real Mac native worker, app adapter/review, durable journal profile,
configuration-only verification and explicit alpha packaging are implemented.
`fb68f74` received independent app/native source review; the UI finding was
reproduced and repaired in `c92b4a9`. Native/helper fixtures never address the
household. No router/account changes or paid/cloud jobs are authorized here.

On 27 October 2026 the owner selected Apache 2.0 and authorized pushing and
publishing the developer alpha. PR #9 consolidates the continuation onto main.
Hosted workflows stay manual; paid cloud review was not requested. Packaging
and controlled wire tests do not establish retail compatibility. Production package
`build/mac-alpha-7422ddc/Thread Network Tool.app` has passed local window
acceptance; its worker/journal bytes match the passing signed-parent wire tests.
Read `MAC-ALPHA-ACCEPTANCE.md` for exact source, tests, artifacts and remaining
controlled retail/distribution gates. The owner has no spare Eero; do not test
a network-wide change on working household Eeros.

Latest local ZIP: `build/Thread-Network-Tool-Mac-alpha-7a50220.zip`
(20,544,294 bytes; SHA-256
`4f7927f6f59595003f7344c0d63122850dd878203ba9500d5a7ab4bb1710e038`).
Its folder is `build/mac-alpha-local-7a50220/`; it includes the unchanged signed
`7422ddc` app, quickstart, notices and updated passing simulator evidence/recipes
from `7a50220`. Every application file/symlink matches the prior package;
recursive strict signatures and ZIP integrity passed. This is a local bundle,
not a newly rebuilt or publicly distributed application. Independent review of
the fix, recipes and final evidence found no actionable findings.

Local follow-up `220bf75` adds the tester guide and screen-to-real-journal
confirmation/recovery acceptance. The three focused tests passed and independent
review found no actionable issue. `MAC-ALPHA-LOCAL-FOLLOWUP.md` records unpacked
app launch and translated x86_64 helper evidence; these do not close retail or
trusted-distribution gates. App binaries still use production code `7422ddc`.
The simulator connectivity defect is now repaired and verified. Read
`SIMULATOR-COUNTER-FIX.md` and `tools/lab/openthread-counter-fix/evidence.json`:
the native counter regression is red/green; the unchanged frozen `787ace4` app
passes all seven gates in corrected image `4340ad60`, with two-process recovery,
one send and real bidirectional connectivity. The fix affects the lab's pinned
OpenThread host stack, not the Mac app or Eero firmware. All task containers
were removed; no repeat operation is queued. The contributor-preview guide,
root CONTRIBUTING.md and issue templates support public developer participation.
See LICENSING.md for the Apache 2.0 decision and RELEASE-ASSETS.md for the
prerelease artifact. Do not revive the old unexplained-simulator-failure status.


---

## Historical account-switch handoff

### Paused handoff — 26 October 2026

Owner requested all agents pause while switching accounts. Do not resume work,
builds, fixtures, pushes, hosted jobs or reviews until the owner resumes it.
All subagents are stopped/completed. No active task-owned lab/build process
remains. No household changes were performed during this application work.

## Exact checkpoint

- Repository: `/Users/richard/thread`, private upstream
  `https://github.com/Guntheruk/thread-network-tool`.
- Branch: `feat/app-move-candidate`.
- Last implementation/test head: `fff2f784b9679cbba8605ef15468b857c6875dc0`.
  This handoff adds documentation only after that head.
- Later work remains local. PR #8 is still the last published candidate; no new
  push, hosted build or cloud review was requested after the owner's cost hold.
- Local candidate workflows are manual-dispatch only. The published remote
  workflows do not acquire that change until it is pushed.

## Built and verified

- Native Flutter Mac application with bundled read-only C++ helper; universal
  local ad hoc package built and inspected on Apple Silicon. This is a native
  desktop application. The localhost web preview is a separate development view.
- Discovery, guided eero copy, Advanced input, credential validation, router
  checks, network-move review, local report preview, and guarded execution code.
  Default consumer packages remain read-only; execution is an explicit isolated
  Linux software-lab profile only.
- Optional existing-Home-Assistant import with explicit server/token action,
  explicit network choice, identity checks and authenticated TLS. At `a2949a68`,
  the actual packaged Mac window imported a complete nonpreferred synthetic
  dataset from a disposable loopback server and rejected an incomplete one.
  No actual household HA server/token was used.
- At `a2949a68`: seven native CTests, 90 Python tests, clean Flutter analysis,
  163 Flutter tests plus one Linux-only skip, and 43 execution checks passed.
- At `fff2f784`: clean full analysis; real-journal adapter lock/retry regression;
  actual-journal startup recovery widget test; 19 fixture tests including the two
  real Unix-socket cases passed. The Linux-only runtime test remained skipped on
  Mac. Independent review closed the adapter initialization finding.

## Actual application move evidence

Frozen `a2949a68` image:
`sha256:6b5f1eb97aa01133fc75316556a07d1c1b552531e7485fa75ae4df2020d8979b`.

- Lost native result: passed after 375 seconds, two real Flutter app processes,
  one Petition/SET, no redispatch on restart, independent convergence checks and
  secret redaction.
- Key-change/older target: failed in recovery after 506.9 seconds. The exact
  assertion and final network-check booleans were discarded. Cause and physical
  convergence remain unknown. No blind retry was performed.
- Both original containers were removed. Evidence:
  `/tmp/tnt-full-app-lab-a2949a68` locally and on linuxbox.
- The next head adds sanitized final app stage/reason/category and seven oracle
  booleans with sample freshness, retaining failure status and verification gates.
- The `fff2f784` image build completed (agent build handle `38722`, exit 0), but
  **no new fixture was started** before the pause. Preserved context and image
  checkpoint: `linuxbox:/tmp/tnt-full-app-lab-fff2f784/paused-state.json`.
  Resume from that record rather than starting an untracked duplicate operation.

## Still unfinished

1. Diagnose the key-change case using the new bounded diagnostics, then verify
   any repair at a frozen head. Existing software-lab success proves no retail
   eero, HomePod or Nest combination.
2. Controlled packaged-Mac sandbox authenticated-read/error-path evidence;
   final exact-candidate window, layout, credential-clearing and report checks.
3. Exact-candidate third-party notices retained alongside the package; reconcile
   stale compatibility, pilot, Android and dependency documentation with PROGRESS.
4. Apple native Mac provisioning remains unresolved. iPhone credential bridge
   and unsigned builds exist, but real device consent/retrieval and secure phone
   transfer are unfinished. A phone companion is optional; keep Mac-first scope.
5. Android credential bridge/APK compiled historically, but it has no usable
   production setup route yet. Windows desktop compiled historically, but live
   discovery/probe networking remains unavailable. Google Home account/trait
   integration is researched but not implemented.
6. Retail-model/firmware compatibility and recovery; trusted distribution signing,
   notarization, clean-Mac/Intel testing and owner license/distribution decisions.

The suggested optional phone product, **Check my home**, remains exploration:
selected-device before/after response checks, not a promised complete Thread map.
AI, Home Assistant, an account and a phone companion are not core requirements.
Internal Mac Thread radio work remains a separate project/chat.

## Resume boundaries

Read AGENTS.md, BUILD-SCOPE, RELEASE-PLAN and PROGRESS. Verify clean branch/head,
the saved paused-state record and original process/container absence before
resuming. Root owns Git. Preserve local-first testing and the current push hold.
Do not change working household devices, reset/re-pair accessories, regenerate
credentials, access a mailbox, purchase, publish or enable telemetry.
