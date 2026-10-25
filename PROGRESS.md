# Progress — 25 October 2026

## Owner scope

Build the four-platform Flutter/C++ application. Automatic transfer of existing accessories from the source Eero network is optional for the first release and must not block the core border-router joining product. Investigate inexpensive fixes separately. Current initial-build acceptance is in docs/BUILD-SCOPE.md.

No home-network writes, resets, accessory removal, credential regeneration, publication, or purchases were performed during this build.

## Implemented

Previous source milestone: `a08b2c0b8b649c0ac34d6f5c3d282ebac5b4c9bd`. This continuation adds live discovery and both direct-native and development HTTP adapters.

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

## Running preview and reproducibility

Synthetic preview remains available at http://127.0.0.1:5187/. The live development helper uses http://127.0.0.1:5188/ with its private session fragment; opening the bare URL intentionally selects the synthetic preview. The browser tab holds the live session. Both modes keep network changes disabled.

Build instructions: README.md and docs/LIVE-READ-CONTRACT.md. Root build output is build/native; optional-probe evidence was built in a temporary directory and must be rebuilt for later use. Live checks used the earlier firewall-approved probe executable plus the new separate discovery executable; no broad firewall rule or home configuration was changed. The SDK is ignored at .tooling/flutter. No remote Git repository exists.

## Next work and gates

1. Real discovery, live UI reads and the direct native adapter are implemented and verified as described above. Preserve the observation/authentication distinction; broader device/platform compatibility still requires separate checks.
2. Package the native Mac application with its helper and dependent libraries, then verify the native window. Full Xcode is missing: xcodebuild explicitly reports that Command Line Tools are insufficient. No valid signing identity was listed by the local keychain check; distribution signing remains unconfigured.
3. Windows and phone native networking, builds/runtime tests and credential-provider integration remain unverified. Their current native entry points explicitly report unavailable.
4. Add supported credential providers; Apple entitlement and actual Google/Nest command support remain unresolved. HA stays optional.
5. Validate joining on a controlled empty/new source network before adding mutating application commands. Existing accessory transfer can remain unsupported with an explicit explanation; never reset devices automatically.
6. Review dependency versions/licenses, complete release notices, choose project license, and arrange signing before publication.

Known limits: the visible live UI is a development web build; no native desktop window or distributable application has been verified. Native parser validation is not complete Thread policy validation or permission to migrate. IPv6 zone identifiers remain unsupported by the initial CLI, and the session adapter currently permits only local/private endpoint ranges. Router restart persistence and universal vendor behavior have not been verified. A shared network may require no action; fresh preferred-keychain onboarding and repair of existing split networks are distinct product cases.
