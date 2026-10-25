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
  provenance, copies deterministic inputs and refuses overwrite. Eight focused
  tests pass and local collection completed without missing inputs. This does
  not choose a project or dependency licence or certify distribution notices.
- `docs/COMPATIBILITY.md` and `docs/PILOT.md` distinguish source, package,
  runtime and external gates. No telemetry collection, account or AI service
  was added. The active goal is not complete.
- Combined continuation validation: Flutter analysis has no issues and all 80
  tests pass. These include mocked provider outcomes, cancellation, join-state
  evidence and consumer layouts. They do not prove Apple/Android device access
  or a real join. The dependency collector's eight tests pass separately.

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
