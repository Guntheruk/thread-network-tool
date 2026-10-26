# Progress — Mac alpha continuation, 26 October 2026

Current owner scope is the real Mac Eero source-network join flow, with guided
manual or existing Home Assistant credentials. Working household devices are
excluded from development/testing. See `docs/MAC-ALPHA.md` for the current scope
and limitations; the historical initial-build and pause entries below do not
supersede this direction.

Integration is on the named `feat/mac-eero-alpha` worktree. It contains the real
Mac source-only Commissioner worker, shared durable no-replay controller,
explicit whole-source review, pinned-endpoint recovery and a separate
`verified_configuration` result that makes no accessory/mesh connectivity claim.
Default packages remain read-only; `TNT_MAC_ALPHA=1` includes the signed worker
and journal. All changes remain local under the existing push/cloud-cost hold.

The production app at `7422ddc8a3b14dec75acb2a005c59198b39d3bc9` is built at
`build/mac-alpha-7422ddc/Thread Network Tool.app`, with a local ZIP beside it.
It includes the real join worker, guided/manual/HA credentials, automatic
bounded checks after explicit confirmation, and durable no-replay recovery.
The actual window accepted a synthetic source dataset; quitting and reopening
cleared credentials. No household discovery, read or change was invoked.
See `docs/MAC-ALPHA-ACCEPTANCE.md` for exact evidence and remaining release gates.

Final Flutter analysis is clean; 178 tests passed with one Linux-only skip.
Other verification: 14 native journal process tests, 51 standalone controller
checks, 110 Python tooling tests (one fresh-source regeneration skip), six scoped
native CTests and five signed-parent loopback wire scenarios. The final worker
and journal are byte-identical to those in the signed wire test package.
Independent native and app reviews found no unresolved P1/P2, including the
automatic-check code at `4437c01`. Later changes clarify copy/manual credentials.
All 44 notice inputs were collected. Local recursive ad hoc signing checks pass;
no Developer ID identity is installed and notarization remains unfinished.

The owner has no spare Eero. An existing household Eero is not an isolated
source for a whole-network change. Retail model/firmware acceptance remains
unverified; working devices stay excluded. This local functional package is
not a claim that the broader release or original multi-platform goal is done.

The frozen Linux scenario `787ace4` still ended `needs_attention` with its
connectivity check false. All other convergence checks were true. A separate,
read-only synthetic ping diagnostic confirmed synchronous reply-before-Done
framing. No repeated move or relaxed connectivity check was used to claim a pass.

## Local completion follow-up

Latest local ZIP: `build/Thread-Network-Tool-Mac-alpha-699df4e.zip`
(20,519,395 bytes; SHA-256
`1e41450d61c7c8640a0f242956905e5892eff3ed12a6954302c402176af1a491`).
Its folder is `build/mac-alpha-local-699df4e/`; it includes the unchanged signed
`7422ddc` app, quickstart, notices and acceptance/diagnostic summaries from
`699df4e`. Binary hashes, recursive signatures and ZIP integrity passed. This
is a local bundle, not a newly rebuilt or publicly distributed application.

At `220bf75`, a new production screen/API/session/adapter acceptance uses the
real native journal and synthetic process replies to confirm exactly one send,
then recovery without restored credentials, automatic checks or a second send.
All three focused integration tests passed without skips; analysis was clean.
Independent review found no actionable finding. A plain-language tester guide
is linked from README. The app binaries remain at `7422ddc`; no production-code
repair was justified by these checks.

The original ZIP was unpacked to a fresh directory; signatures passed and the
native window launched from that exact path with discovery idle. The packaged
parser and move worker also passed x86_64-pinned checks under Rosetta from a
signed sandbox parent. This does not cover physical Intel, the full translated
Flutter app, or clean-Mac installation. See `docs/MAC-ALPHA-LOCAL-FOLLOWUP.md`.
No household calls, pushes, hosted jobs or publication were performed.

A single frozen `787ace4` diagnostic repeated the key-change failure: cross-
original-network pings failed in both directions, while moved-source peers
communicated. Explicit packet-loss output excludes discarded reply parsing;
underlying simulator routing/key/address state remains unresolved. All six
configuration checks passed, connectivity stayed false, and the app correctly
retained `needs_attention`. The disposable container was removed. Exact evidence
and remaining scope are in the follow-up record; no production fix was invented.


---

# Progress — 25 October 2026

## Owner scope

Build the four-platform Flutter/C++ application. Automatic transfer of existing accessories from the source Eero network is optional for the first release and must not block the core border-router joining product. Investigate inexpensive fixes separately. Current initial-build acceptance is in docs/BUILD-SCOPE.md.

No home-network writes, resets, accessory removal, credential regeneration, public release or purchases were performed during this build. The owner subsequently authorized a private GitHub repository and PR reviews.

The owner also clarified that ordinary users must not need to understand or find
hex datasets unaided. Planned credential setup combines supported consent-based
retrieval with guided vendor-app copying; the observed eero app exposes an
Active operational dataset field. See docs/INTERFACE.md. The continuation below
implements guided copying and native credential bridges; real provider access
and platform runtime evidence remain separate gates.

## First-release continuation

The owner explicitly requested an active completion goal, focused agents and
continued implementation beyond a working window. `docs/RELEASE-PLAN.md` records
the full acceptance. The pasted strategy informs local/no-account operation,
compatibility evidence, recovery and a small debugging pilot; it does not
authorize licence selection, publication, analytics or signup collection.

- Guided eero setup and Advanced manual entry replace the raw-only live dialog.
  Copying uses the observed Active operational dataset field, with no fixed
  vendor menu path or credential regeneration. Narrow layouts, large text,
  cancelled requests, malformed input and generic errors are covered.
- The macOS Apple bridge checks availability separately from an explicit
  credential request, bounds calls, drops late responses after cancellation and
  prevents overlapping native prompts. Missing entitlement has an explicit
  fallback. ThreadNetwork is weak-linked for the macOS 12 deployment target;
  final packaged load commands and runtime are recorded separately when checked.
  Real credential retrieval remains unverified and no entitlement was granted.
- The Android bridge uses the pinned Google Thread Network SDK 16.3.0 with
  explicit consent, operation IDs, bounded calls and cancellation. API signatures
  were checked against the official AAR. Kotlin compilation and device consent
  remain unverified; the Android SDK and JDK are not installed on this Mac.
  The bridge is not yet connected to a usable Android discovery/read workflow.
- A pure join assessment, confirmation snapshot and synthetic actuator harness
  distinguish readiness, command acceptance, pending observation and verified
  completion. Review repairs bind confirmation to the selected source/target,
  prevent duplicate dispatch, invalidate confirmation on restart and require
  fresh accessory evidence. This adds no live device command or UI join route.
- Network-wide Pending Dataset migration and a vendor single-router join are
  separate operations. The earlier Eero approach was network-wide. Work on an
  isolated OpenThread simulation must not be represented as vendor compatibility.
- The local notice collector resolves source revisions and SDK package licence
  provenance, copies deterministic inputs and refuses overwrite. Thirteen focused
  tests pass and local collection completed without missing inputs. This does
  not choose a project or dependency licence or certify distribution notices.
- `docs/COMPATIBILITY.md` and `docs/PILOT.md` distinguish source, package,
  runtime and external gates. No telemetry collection, account or AI service
  was added. The active goal is not complete.
- Combined continuation validation: Flutter analysis has no issues and all 80
  tests pass. These include mocked provider outcomes, cancellation, join-state
  evidence and consumer layouts. They do not prove Apple/Android device access
  or a real join. The dependency collector's eight tests pass separately.
- Independent review of committed head `7874ce0` found no new credential/setup
  defect and three join/notice issues. The repairs keep incomplete observations
  pending until the observation period ends, reserve a source router across
  distinct operation IDs, and reject missing/dirty dependency revision evidence.
  The repaired working tree has clean analysis, 84 passing Flutter tests and 13
  passing collector tests. Fresh collection against the new package completed.
- Source `7874ce0` built a new universal Mac app at
  `build/macos-guided-7874ce0/Thread Network Tool.app`. App/helper signatures pass
  strict recursive checks, and both architectures load ThreadNetwork with
  `LC_LOAD_WEAK_DYLIB`. The native window shows all guided choices, reports the
  missing Apple entitlement, and rejects a malformed synthetic input with a
  cleared field. After the Mac was unlocked, the valid TestMesh fixture was
  accepted through the guided flow. Quitting the new package and reopening it
  cleared the test credentials and returned to the initial state. No household
  credentials or network change was used. Screenshots are ignored local artifacts.
- Draft PR #2 is stacked on #1 for source review. The protocol simulation runs
  separately from the application; its evidence is recorded below.
- GitHub Codex review of `7874ce0` found that the synthetic harness could ignore
  a stop-observation transition. A regression reproduced `complete` after stop;
  the fix updates the authoritative reservation and rejects stale callbacks.
  Final continuation analysis is clean and all 86 Flutter tests pass. This
  repairs simulated control flow, without enabling any network write.
- GitHub Codex review of `73dd4882a6b1aaddbc5e2cdc122a29347a6a223d`
  completed with no unresolved findings. After the owner resolved the GitHub
  account blocker, run `40218431367` attempt 2 passed native core tests on
  Ubuntu/macOS and Flutter analysis, tests and the release web build. The
  base PR's previously blocked run was separately requested again.
- The final isolated OpenThread lab passed with one source-network Pending
  Dataset SET: both source routers received the update, converged on the target
  dataset and partition, retained router roles and passed connectivity. The
  target remained unchanged. The exact frozen driver hash, image/source pins,
  redacted report and an earlier ping timeout are in `docs/PROTOCOL-LAB.md`.
  Runtime used a no-network, read-only container without host devices or
  household credentials, and the container was removed after completion.
  Six Python driver tests pass. This validates simulated Thread-stack behavior,
  not the application's Commissioner/Border Agent path or any vendor device.
- `docs/NETWORK-MOVE-PLAN.md` names the next application slice: separate source
  and target access, authenticated reads of observed source routers, explicit
  controlled-empty-source evidence and a network-wide review. The existing
  single-router model must not be relabelled as that network operation.

## Source-network review continuation

- Separate source and target credentials now stay in memory with explicit roles.
  Authenticated reads retain identity and Active Timestamp privately; public
  reports expose role counts without datasets, keys, endpoints or household IDs.
- The review includes all observed source candidates, requires matching fresh
  reads and controlled empty-source attestation, and blocks pending changes,
  inconsistent timestamps or stale evidence. It states the whole-network scope
  and unknown offline devices. Re-import, re-discovery, changed reads and expiry
  invalidate the review. There is no dispatch API or native write command.
- Root integration found that the UI's initial delay options were all below the
  planner's minimum. The shared flow now offers 5, 15 or 30 minutes. Two widget
  tests exercise the real NativeLiveApi and LiveSession, faking only native read
  replies: two source routers pass together, and one pending source blocks the
  review. Tests also cover role report redaction and visible review expiry.
- Flutter analysis passes. The real session/UI integration tests pass; the six
  source-network widget tests pass at normal and narrow/enlarged text settings.
  Planning, HTTP adapter and loopback access-boundary scripts pass. All four
  Commissioner-enabled native CTests pass, including raw-wire timestamp
  encoding. CI now runs the planning and loopback scripts as well as widgets.
- Windows PR #4 at `6498a9ed83b5a6d79d69e39b483faf37aa2a35e8` passes both
  the native parser/CLI build and Flutter desktop build in run `40220629150`.
  Codex review has no unresolved findings. This is build evidence, not Windows
  discovery or router communication. Android PR #5 adds a real debug APK
  compile gate; its first hosted run is in progress and device consent remains
  unverified. Neither PR is merged or released.
- The locally signed universal Mac package built from `4cc1e80` opened the new
  workflow. Distinct synthetic LabTarget and LabSource datasets populated the
  correct roles through the real bundled parser; the report showed both roles
  without network names or credentials. After confirmed process exit and
  reopening, both roles were empty. The 5-minute default and disabled move
  control were visible. Screenshots are local ignored artifacts under
  `build/evidence/native-move-*`. No discovery or household read was performed.
  The first automated paste left the field empty; typing the fixture succeeded.
- Independent review found inspection-only probes could leave a prepared move
  review and its role evidence reusable. A new probe now invalidates the review
  and that router's role evidence before the native call, including failures.
  Repreparing requires a fresh role check. The regression first reproduced the
  stale ready result and now passes. Final analysis is clean, all 96 Flutter
  tests pass, and the planning/API/loopback scripts pass after this repair.
- Follow-up review found that a failed probe could erase a source router
  identified only by an earlier authenticated read. Source membership now
  survives failed and generic probes within the same discovery and source
  credential generation; current successful reads are still required. Target
  credential replacement retains that membership. The focused regression
  passes and independent review found no further census issue.
- Hosted CI at `03f8f60` exposed two portability failures after Flutter analysis
  and all 96 widget tests passed: the optional Commissioner header was included
  in core-only builds, and Dart temporary staging was not private on Linux.
  The include is now conditional and POSIX staging uses atomically private
  `mktemp -d` before any session secret is written. The local access-boundary
  regression and direct macOS core-only compilation pass; fresh hosted CI is
  required to verify Linux and the final combined head.
- Hosted Checks run `40225229885` passed at `fcc608d`, including the repaired
  core-only builds and Linux private staging. Codex review reported no new major
  issue on this head, but an earlier finding about review freshness across shared
  browser tabs remains open and is being repaired separately.
- Android PR #5 at `c60c5b4f0221fef9035700bcf947df8524605c62` passed debug APK
  build run `40224904977` and all generic checks in `40224904969`. The APK was
  nonempty; installation, device launch and Google consent remain unverified.
  Codex review was requested on that exact head. No PR has been merged.
- The shared-session review finding now has a reproduced regression and repair.
  A screen checks its review ID against the authoritative session while visible
  and when resumed; missing, changed, expired or unverifiable reviews lose their
  ready status. Generation checks discard late results, lookups do not overlap,
  and hidden screens do not issue checks. Thirteen focused widget/integration
  tests pass, including two screens backed by one real `LiveSession` with only
  native IO replaced. Full candidate checks remain separate validation.

## Implemented

Previous source milestone: `563ffe0df6a092246aa72e847734b8e7eafdb03a`. This continuation simplifies the interface using the Recursive Systems visual direction, records Google Home and migration beta scope, and sets up GitHub PR checks.

- Bounded C++ dataset parser and C ABI; rejects malformed/duplicate/missing/oversized TLVs, invalid UTF-8 and unsupported page/channel combinations. Page-0 channel mask follows raw MeshCoP MSB-first encoding.
- CLI inspect and optional pinned OpenThread Commissioner read-only probe. Credentials enter via stdin; reports omit Network Key, PSKc and raw datasets.
- Probe uses Connect plus Active/Pending GET only; no Petition/SET/network-sync path. Nonzero error/partial/mismatch exits; POSIX 30-second process deadline and generic exception handling.
- Flutter three-step synthetic assessment with target selection, masked import, safe fixture, explicit unknowns, disabled join, and redacted report preview.
- Native Dart parser adapter and a real FFI smoke tool. It is not presented as live discovery in the app.
- Generated platform projects for Mac/Windows/Android/iOS plus web preview. Project-local Flutter SDK installed and checksum verified. Full Xcode 27.1 was subsequently installed and first-run setup completed by the owner.
- Bounded macOS DNS-SD discovery of Thread Border Agent advertisements with allowlisted metadata, resolve/remove handling and explicit non-macOS unsupported status.
- Shared Dart read session: deduplicated router observations, private endpoint handles, one read at a time, credential validation and expiry of discovered handles.
- Live Flutter screen with credential import, individual authenticated reads, timestamps, explicit mismatch/partial/timeout outcomes, disabled join and a report omitting household identifiers.
- Direct native macOS adapter invokes the engine without HTTP. Missing helpers and unsupported Windows/phone networking are shown as unavailable. Native window packaging, discovery and synthetic import were subsequently verified as recorded below.
- Optional loopback development helper with exact Host/Origin checks, temporary bearer access, bounded bodies and native subprocesses, private session-file publication and no credential persistence. Browser refresh retains live mode without browser storage.
- macOS runner now resolves `Contents/Helpers/thread-network`. CMake installs the helper and its core library with relative load paths. The parent retains App Sandbox with client/server network access for UDP; the helper has only sandbox/inherit entitlements. Local-network purpose and Bonjour service are declared.
- Native `capabilities` command reports compiled read support without credentials or network activity. Packaging requires a read-only authenticated-probe build, defaults to Intel/Apple Silicon universal output, checks app/helper architecture compatibility and refuses to overwrite an existing package.
- Packaging signs nested code before the app, supports local ad hoc signatures and an explicitly selected Developer ID identity, and verifies nested signatures. Developer ID signing requests secure timestamps. It does not install Xcode, change the selected toolchain, notarize or publish.
- Shared Flutter theme follows the inspected Recursive Systems Elixir neutral/blue palette, flat surfaces and compact controls. The live screen gives router checks priority and puts technical fields behind disclosure; read-only scope and distinct outcomes remain visible.
- Google Home Android/iOS capability, consent and credential routes are documented in docs/GOOGLE-HOME.md. No Google account bridge or Nest model is implemented/verified. Separate router/network/accessory beta flows, sleepy timing, controller authority and recovery requirements are planned in docs/MIGRATION-BETA.md; no mutation command was added.
- Private repository `https://github.com/Guntheruk/thread-network-tool` created at the owner's request, with committed baseline `563ffe0` on main. Work continues on `feat/clear-interface`. PR workflow uses read-only GitHub token permissions, pinned action revisions and synthetic/core checks without home access.

## Verification

- Native Debug and Release CTests passed. Tests use always-on checks, including independent raw-wire channel mask fixtures.
- Optional Commissioner build passed against pinned source `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae`.
- Dart FFI smoke passed against the actual macOS shared library: accepted synthetic dataset metadata, rejected malformed input and duplicate TLV.
- Flutter analysis passed with no issues; 7 widget tests passed, including compact mobile viewport and synthetic labeling when a native inspector is injected.
- Flutter release web build passed. It emitted a Cupertino font-family warning; the inspected UI uses Material icons and rendered normally.
- In-app browser visual check passed for target selection and review; join control visibly disabled. Local screenshot: build/evidence/preview-review.png (ignored build artifact).
- One authorized live Eero read at 14:30 UTC returned the built-in timeout (exit 124). Authentication, current dataset, and pending state remain unknown from this attempt. No key material was logged. The subsequent firewall UI inspection could not proceed because the Mac was locked. Do not attribute the timeout to the firewall as an established cause.
- A retry at 16:05 UTC, after the owner allowed the helper's Little Snitch connection, completed successfully (exit 0): authenticated=true, identity_match=match, active_status=read, pending_status=empty. This verifies the new native probe against one Eero; it does not establish other vendors, restart persistence, or app UI integration. The probe performed GET operations only; household identifiers and credentials remain outside this repository.
- Discovery Debug/Release CTests passed (2/2 in each configuration). A live scan found eight unique router advertisements and one advertised network identity; advertisements alone do not prove router health.
- Live interface verification: selected the previously authorized Eero in the UI and observed completed authentication, imported identity match, active read and empty pending state. Screenshot: build/evidence/live-router-read.png (ignored).
- After restarting the final helper, browser reload preserved the live session fragment and mode. A fresh UI discovery and selected Eero read succeeded again at 16:18 UTC.
- Direct native Flutter adapter also completed discovery/import/one real Eero read without the browser or HTTP server. This verifies its Dart-to-native read path, not a packaged Flutter desktop window.
- Full Flutter analysis clean; 20 tests passed including native adapter and unavailable behavior. Web release rebuilt successfully; known unused Cupertino font-family warning remains.
- Local-helper regression script passed: unauthorized/foreign-origin/rebinding requests rejected, endpoint handles bound to discovery and expired, errors/results redacted, private session files not overwritten, and a slow-drip request closes at the total five-second deadline. Independent review findings on atomic session-file privacy and total request time were fixed and re-reviewed.
- In the current workspace, the pinned Commissioner build produced an `arm64`/`x86_64` helper targeting macOS 12.0. Native CTests passed 3/3, including capabilities; installed payload reports authenticated-probe support and `network_writes: false`. Dynamic dependencies are the bundled core plus system libraries/frameworks. Intel execution has not been tested.
- The universal relocation smoke test passed after moving a synthetic app and deleting its native build tree. A separate locally signed sandbox parent successfully launched its sandbox-inheriting helper; valid synthetic inspection returned success and invalid inspection returned a redacted failure. The test passes outside Codex's enclosing process sandbox; inside it the signed parent aborts before `main`. This is not proof of a packaged Flutter window or sandboxed networking.
- Full universal authenticated-probe payload staging passed after correcting the dependency scanner to ignore each architecture's `otool` filename heading. Installed capabilities ran successfully without credentials or network calls.
- Full Flutter analysis is clean and all 24 tests pass, including bundled-helper lookup, missing-helper handling and explicit override behavior. Plists/project file and scheme pass static syntax checks. Independent packaging review findings on timestamps and recursive verification were fixed and verified; the UDP receive entitlement was corrected against current Apple documentation.
- Before full Xcode was installed, the macOS build stopped at its preflight because only Command Line Tools were available. The later packaged-app verification below supersedes this blocker; Developer ID distribution signing remains unconfigured.
- Interface continuation: full Flutter analysis passed, all 26 tests passed, and the release web build succeeded. Tests cover collapsed details, distinct verification/failure states, narrow screens and enlarged text under the shared theme. The existing unused Cupertino font warning remains; displayed icons are Material icons.
- Updated the running preview's generated web assets without restarting its private session. The narrow browser view visibly shows compact router rows; opening and closing details worked. Screenshot: `build/evidence/interface-compact.png` (ignored, local only). This used existing session observations, not new household discovery or reads. Native desktop-window verification was pending Xcode at that stage and subsequently completed below.
- PR workflow YAML and command paths were validated locally. Hosted GitHub checks are a separate result and must be read from the PR; no CI pass is implied by local tests.
- Source head `dfa41386139710a63ed81fdcaa1c75c9272bda31` built a complete locally signed macOS app with Xcode 27.1 (27A9275), selected per command through `DEVELOPER_DIR`. Strict recursive signature verification passed; both app and helper contain arm64/x86_64 slices. The native Flutter window launched on this Apple Silicon Mac.
- From the packaged native window, bounded discovery completed with eight unverified advertisements, both before and after restarting the app. Process inspection confirmed the bundled helper was a child of the app and exited after the first scan. The native dialog accepted a synthetic dataset and rejected malformed input with a cleared field and generic error. The redacted report contained counts and zero authenticated reads, excluding household identifiers. Restarting returned to the initial state without imported test credentials. Local screenshot: `build/evidence/native-macos-discovery.png` (ignored).
- No household credentials, authenticated router read, or network write was used for this packaged-app verification. The packaged sandbox's DTLS path and Intel execution remain unverified. The prior direct-adapter authenticated read is separate evidence.
- Draft PR #1 remains unmerged. Independent source review and GitHub Codex review of `dfa4138` found no concrete findings. Hosted run `40213499083` did not start because of GitHub's account billing/spending restriction; local runtime success is not a hosted CI pass.

## Running preview and reproducibility

Synthetic preview remains available at http://127.0.0.1:5187/. The live development helper uses http://127.0.0.1:5188/ with its private session fragment; opening the bare URL intentionally selects the synthetic preview. The browser tab holds the live session. Both modes keep network changes disabled.

Current source workspace is `/Users/richard/thread`, cloned locally from the clean committed source in `/Users/richard/thread-network-tool`. The earlier folder and its running preview remain intact; prior UI screenshots and preview build artifacts remain there. Git origin is the private GitHub repository; the earlier local source remote is retained as `source-local`. The ignored Flutter SDK link currently resolves to the earlier workspace's SDK; portable builds can set `TNT_FLUTTER_BIN` explicitly.

Build instructions: README.md, docs/LIVE-READ-CONTRACT.md and docs/MACOS-BUILD.md. Current optional-probe output is `build/native-probe`; the complete local app is `build/macos-package/Thread Network Tool.app`. The earlier `build/native-payload/Contents` remains a helper/library payload only. Earlier authenticated checks used the firewall-approved probe executable plus a separate discovery executable. Packaged-app verification added two read-only discovery scans and synthetic imports; no home configuration changed. No public release exists.

## Next work and gates

1. Real discovery, live UI reads and the direct native adapter are implemented and verified as described above. Preserve the observation/authentication distinction; broader device/platform compatibility still requires separate checks.
2. The packaged macOS window, bundled helper, sandboxed discovery and synthetic imports are verified. Verify a specifically authorized authenticated read from that packaged sandbox next; direct-adapter reads do not establish this path. Distribution signing remains unconfigured, and Intel execution has not been tested.
3. Windows and phone native networking, builds/runtime tests and credential-provider integration remain unverified. Their current native entry points explicitly report unavailable.
4. Add consumer credential setup: a guided eero dataset-copy route, then test the documented Apple macOS/iPhone consent APIs and Android Thread SDK. Keep raw import under Advanced and check returned network identity. Apple entitlement/runtime access and actual Google/Nest command support remain unresolved. HA stays optional.
5. Validate joining on a controlled empty/new source network before adding mutating application commands. Existing accessory transfer can remain unsupported with an explicit explanation; never reset devices automatically.
6. Review dependency versions/licenses, complete release notices, choose project license, and arrange signing before publication.

Known limits: the native Mac app is a locally signed development build, without Developer ID signing or notarization. Its authenticated router-read path is still unverified. Native parser validation is not complete Thread policy validation or permission to migrate. IPv6 zone identifiers remain unsupported by the initial CLI, and the session adapter currently permits only local/private endpoint ranges. Router restart persistence and universal vendor behavior have not been verified. A shared network may require no action; fresh preferred-keychain onboarding and repair of existing split networks are distinct product cases.

## Integrated execution and Apple continuation — 25 October 2026

- `c4d0d309d1d8ada09f962dae143b1b5b336e323d` combines the isolated native
  Commissioner adapter, durable journal/controller, legacy TLV 74 support and
  strict raw Pending GET. A fresh optional native build at that exact head
  passed all seven CTests. This does not extend the earlier frozen Docker
  runtime results to changed source or establish vendor support.
- Confirmation replay now returns the original dispatch evidence rather than
  incorrectly reporting that nothing was sent. Controller startup and adoption
  of another process's operation reset inherited observation intervals.
  Independent review found no further actionable defect in these repairs;
  39 real-journal Dart checks and 11 native journal process tests passed.
- The iOS provider slice `fd41149d78315c8ceb22d62c6883ee61299a972a` passed
  22 focused provider/dialog tests, 11 native gate checks, a full unsigned iOS
  build and a full unsigned build with the credential branch enabled. Independent
  review found no concrete blocker. Device provisioning, consent/retrieval and
  secure phone-to-Mac transfer remain unverified/unfinished respectively.
  Apple's native macOS provisioning route is not established; see APPLE-ACCESS.
- Hosted checks for the read-lab input repair `8a230693531776fdaa1534a6c7c6230762e2b0e3`
  passed in run `40238414111`. Codex review was requested on that exact head.
- The complete screen-to-session-to-native move flow is still being implemented.
  Its isolated profile must bind the original simulator processes and complete
  datasets, fence before dispatch and verify outcomes after worker termination.
  Default consumer builds remain read-only. No household operation was performed.
- Mac internal Thread radio research/implementation now belongs to the separate
  chat and repository. This app's completion work does not depend on private
  radio access. The older privacy/lighting and open-source strategy context
  informs simple local operation; historical assistant proposals are not new
  requirements or verified market claims.
- Final combined source `04f3b852e8f4f3257bac1c64bbcddf81e6cfbf24` passed
  clean Flutter analysis, all 105 Flutter tests, 39 execution checks and all
  71 tooling/process tests with real source reproducibility enabled. Independent
  delivery/raw-Pending review found no actionable blocker. Draft PR #8 records
  this candidate; the full app execution flow remains a separate integration.
- The universal Mac package at `build/macos-review-04f3b85/Thread Network Tool.app`
  built and passed strict recursive signature checks. Its exact executable
  launched; the guided setup and safe Apple-unavailable fallback were verified
  in the native window. This check used no household credentials or discovery.
  The package retains the exact dependency patch/tree provenance alongside it.
- Hosted unsigned iOS run `40241323165` passed, including the enabled-provider
  compile branch. In run `40241323050`, both native OS jobs and the complete
  Flutter job passed; the tooling job failed because its journal tests lacked
  the helper executable environment. CI now builds those fixtures and provides
  their paths before the full tooling suite. Fresh hosted proof is pending.
- The tooling fixture repair at `53a740875d77f9c196d6772479ea181ab6ce07af`
  passed all hosted Checks in run `40241784835`; the unsigned iOS workflow
  also passed in `40241784788`.
- PR #8 review found three actionable issues despite earlier local reviews:
  editable provenance could authorize unrelated dependency source; transient
  journal contention poisoned cached recovery futures; and a sample spanning
  the observation deadline could throw instead of remaining pending. Regressions
  reproduced all three. Source verification now uses a committed independently
  reconstructed tree digest. Recovery evicts failed cached attempts and requires
  the sample itself to reach the deadline. The repaired slices passed 37 focused
  source/resolver/notice checks and 43 real-journal execution checks respectively.
- Verification of the exact generated source also passed in the frozen Linux
  image's Python 3.10.12. CMake now permits that interpreter for verification;
  preparing archives still requires the safe `tarfile.data_filter` API. Python
  tar transport preserved the committed tree; Mac tar AppleDouble extras remain
  invalid inputs.
- The owner questioned hosted-check costs. Further pushes and cloud review
  requests are on hold; implementation and verification continue on the Mac and
  the existing Linux machine. The completed hosted checks remain historical
  evidence, not permission to trigger more jobs.

## Local application integration continuation

- PR #8 at `51a2eae9d218abcec92f05c934be38205d0040c7` completed its already
  requested Codex review with no unresolved findings. Its two already-triggered
  hosted workflows passed. No later push/review was requested after the cost hold.
- Local branch `feat/app-move-candidate` assembles the actual screen/API/session,
  journal and native worker. Startup recovery was repaired to precede discovery;
  an actual journal plus unavailable fixture regression passed. Native ownership
  checks now bind the actual IPv6 destination and reject shared sockets. Both
  Linux regressions failed on the old verifier and passed with the repair.
- The `313ebeb` Mac package built and passed recursive signature verification;
  its native window displayed Network to keep / Network to move. Full local
  Flutter analysis was clean; 109 tests passed with two explicit skips. The
  startup regression was then run with its actual helper and passed separately.
- The local Linux Flutter runner is pinned to image
  `sha256:fb2cad7152fcaa07415e9fa1ab14a64374a60996b60fcd4a16f317adb4948994`.
  Its synthetic widget smoke passed offline, unprivileged and with a read-only
  root. Preparation evidence is on linuxbox under `/tmp/tnt-flutter-runner-20261025`.
- The first complete app fixture at `313ebeb` failed during simulator setup,
  before launching the app: random numeric node IDs exceeded the pinned 1..33
  range. `801328c` fixes this with namespace-local IDs; its regression reproduced
  the failure and all nine fixture tests then passed.
- The first `801328c` app attempt exposed missing derived package_graph metadata
  in the runner command. A no-fixture compile smoke verified the corrected
  command after checking the cached pubspec/lock match. The corrected attempt
  reached real dialogs, role-bound router reads and the review, then failed
  during native preparation before confirmation. It is not a completed move.
  Task-owned evidence and exact command hashes remain on linuxbox under
  `/tmp/tnt-full-app-lab-313ebeb1` and `/tmp/tnt-full-app-lab-801328c4`.
- `8f47fa4` adds only fixed, correlated preparation-failure diagnostics to the
  explicit lab test and records optional credential/phone scope. A fresh local
  diagnostic candidate is being tested. No actual app convergence, vendor
  compatibility, real iPhone retrieval or phone-to-Mac transfer is claimed.

## Local candidate evidence — 26 October 2026

- Hosted build/test workflows now use manual dispatch only in the local
  candidate, and `tools/check_local.sh` provides local verification. These
  changes have not been pushed; no new hosted build or cloud review was
  requested after the owner's cost concern.
- At `a2949a68ec159bdc4b76304ef955bb028f5f097d`, local verification passed
  seven native CTests, 90 Python tests, Flutter analysis, 163 Flutter tests
  (one explicit Linux-only runtime skip), and 43 standalone execution checks.
  The fresh independently reconstructed Commissioner source verified before
  and after the build. An older prepared cache failed integrity and was not
  reused; verification was not relaxed.
- That head's universal locally signed Mac package passed strict recursive
  signature verification. Its exact executable was inspected through the native
  window. An optional Home Assistant import against a disposable loopback-only
  synthetic server waited for explicit network selection, cleared the token,
  fetched only the selected nonpreferred network, passed native validation and
  displayed **Credentials ready for SyntheticTwo**. An incomplete fixture was
  refused. No real Home Assistant server/token or household router was used.
  The test app and fake server were stopped afterward.
- The optional Home Assistant route uses only existing read-only Thread APIs.
  Independent review reproduced and closed the initial HTTPS/plaintext defect;
  explicit TLS now validates the original hostname over the pinned address.
  Correct-host/trusted-CA success, wrong-host/untrusted rejection and stalled-TLS
  cancellation were tested. Live server compatibility is still unverified.
- The actual isolated Flutter-screen workflow at the same head used frozen
  image `sha256:6b5f1eb97aa01133fc75316556a07d1c1b552531e7485fa75ae4df2020d8979b`.
  Lost-result recovery passed in 375 seconds with two real app processes,
  one Petition/SET, zero restart dispatches, full independent verification and
  secret redaction. Key-change reached recovery but exited unsuccessfully after
  506.9 seconds. Its supervisor stayed alive, but the exact assertion and final
  oracle flags were not retained; physical nonconvergence is unproven. Both
  original containers were removed and neither operation was retried.
  Exact evidence and reproduction recipes remain under
  `/tmp/tnt-full-app-lab-a2949a68` on linuxbox, with sanitized evidence copied
  to the same local path. This is mixed evidence, not app runtime acceptance.
- Review found an additional cached adapter-initialization failure. A real
  journal lock reproduced `journal_busy` persisting after the lock released.
  The narrow repair evicts failed attempts, shares in-flight attempts and
  retains successful initialization; its real-lock regression passes. The
  local check script now includes that regression.
- The lab failure path now retains only fixed app outcome categories and seven
  allowlisted independent oracle booleans, with sample count/age. Unknown
  fields, identifiers, addresses, datasets and raw errors remain excluded.
  This improves the next diagnosis; it does not establish the previous failure's
  cause or relax the timing/verification requirements.
- The optional mobile product remains an exploration. A selected-accessory
  **Check my home** workflow could provide value beyond credential transfer;
  it is not an approved expansion of first-release scope. Mac-first delivery
  continues and the desktop does not require a phone companion.

Owner pause: all agents stopped for an account switch. The `fff2f784` image
build completed, but its new fixture never started; no task-owned build or lab
process remains active. Resume from `docs/RESUME.md` only after owner direction.
