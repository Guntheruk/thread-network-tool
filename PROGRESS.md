# Progress — 25 October 2026

## Owner scope

Build the four-platform Flutter/C++ application. Automatic transfer of existing accessories from the source Eero network is optional for the first release and must not block the core border-router joining product. Investigate inexpensive fixes separately. Current initial-build acceptance is in docs/BUILD-SCOPE.md.

No home-network writes, resets, accessory removal, credential regeneration, public release or purchases were performed during this build. The owner subsequently authorized a private GitHub repository and PR reviews.

## Implemented

Previous source milestone: `563ffe0df6a092246aa72e847734b8e7eafdb03a`. This continuation simplifies the interface using the Recursive Systems visual direction, records Google Home and migration beta scope, and sets up GitHub PR checks.

- Bounded C++ dataset parser and C ABI; rejects malformed/duplicate/missing/oversized TLVs, invalid UTF-8 and unsupported page/channel combinations. Page-0 channel mask follows raw MeshCoP MSB-first encoding.
- CLI inspect and optional pinned OpenThread Commissioner read-only probe. Credentials enter via stdin; reports omit Network Key, PSKc and raw datasets.
- Probe uses Connect plus Active/Pending GET only; no Petition/SET/network-sync path. Nonzero error/partial/mismatch exits; POSIX 30-second process deadline and generic exception handling.
- Flutter three-step synthetic assessment with target selection, masked import, safe fixture, explicit unknowns, disabled join, and redacted report preview.
- Native Dart parser adapter and a real FFI smoke tool. It is not presented as live discovery in the app.
- Generated platform projects for Mac/Windows/Android/iOS plus web preview. Project-local Flutter SDK installed and checksum verified; no full Xcode installed.
- Bounded macOS DNS-SD discovery of Thread Border Agent advertisements with allowlisted metadata, resolve/remove handling and explicit non-macOS unsupported status.
- Shared Dart read session: deduplicated router observations, private endpoint handles, one read at a time, credential validation and expiry of discovered handles.
- Live Flutter screen with credential import, individual authenticated reads, timestamps, explicit mismatch/partial/timeout outcomes, disabled join and a report omitting household identifiers.
- Direct native macOS adapter invokes the engine without HTTP. Missing helpers and unsupported Windows/phone networking are shown as unavailable. Native window packaging remains unverified.
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
- The full macOS build command stops at its Xcode preflight: only Command Line Tools are installed. No complete Flutter app package, native window or Developer ID distribution signature has been produced.
- Interface continuation: full Flutter analysis passed, all 26 tests passed, and the release web build succeeded. Tests cover collapsed details, distinct verification/failure states, narrow screens and enlarged text under the shared theme. The existing unused Cupertino font warning remains; displayed icons are Material icons.
- Updated the running preview's generated web assets without restarting its private session. The narrow browser view visibly shows compact router rows; opening and closing details worked. Screenshot: `build/evidence/interface-compact.png` (ignored, local only). This used existing session observations, not new household discovery or reads. Native desktop-window verification remains pending Xcode.
- PR workflow YAML and command paths were validated locally. Hosted GitHub checks are a separate result and must be read from the PR; no CI pass is implied by local tests.

## Running preview and reproducibility

Synthetic preview remains available at http://127.0.0.1:5187/. The live development helper uses http://127.0.0.1:5188/ with its private session fragment; opening the bare URL intentionally selects the synthetic preview. The browser tab holds the live session. Both modes keep network changes disabled.

Current source workspace is `/Users/richard/thread`, cloned locally from the clean committed source in `/Users/richard/thread-network-tool`. The earlier folder and its running preview remain intact; prior UI screenshots and preview build artifacts remain there. Git origin is the private GitHub repository; the earlier local source remote is retained as `source-local`. The ignored Flutter SDK link currently resolves to the earlier workspace's SDK; portable builds can set `TNT_FLUTTER_BIN` explicitly.

Build instructions: README.md, docs/LIVE-READ-CONTRACT.md and docs/MACOS-BUILD.md. Current optional-probe output is `build/native-probe`; `build/native-payload/Contents` is an installed helper/library payload, not a complete application. Earlier live checks used the firewall-approved probe executable plus a separate discovery executable. Packaging and interface work made no home-network calls or configuration changes. No public release exists.

## Next work and gates

1. Real discovery, live UI reads and the direct native adapter are implemented and verified as described above. Preserve the observation/authentication distinction; broader device/platform compatibility still requires separate checks.
2. Run the prepared macOS packaging workflow and verify the native window, bundled helper and sandboxed discovery/read path after full Xcode is installed. Command Line Tools are insufficient. No valid signing identity was listed by the local keychain check; distribution signing remains unconfigured.
3. Windows and phone native networking, builds/runtime tests and credential-provider integration remain unverified. Their current native entry points explicitly report unavailable.
4. Add supported credential providers; Apple entitlement and actual Google/Nest command support remain unresolved. HA stays optional.
5. Validate joining on a controlled empty/new source network before adding mutating application commands. Existing accessory transfer can remain unsupported with an explicit explanation; never reset devices automatically.
6. Review dependency versions/licenses, complete release notices, choose project license, and arrange signing before publication.

Known limits: the visible live UI is a development web build; no native desktop window or distributable application has been verified. Native parser validation is not complete Thread policy validation or permission to migrate. IPv6 zone identifiers remain unsupported by the initial CLI, and the session adapter currently permits only local/private endpoint ranges. Router restart persistence and universal vendor behavior have not been verified. A shared network may require no action; fresh preferred-keychain onboarding and repair of existing split networks are distinct product cases.
