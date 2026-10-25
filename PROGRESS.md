# Progress — 25 October 2026

## Owner scope

Build the four-platform Flutter/C++ application. Automatic transfer of existing accessories from the source Eero network is optional for the first release and must not block the core border-router joining product. Investigate inexpensive fixes separately. Current initial-build acceptance is in docs/BUILD-SCOPE.md.

No home-network writes, resets, accessory removal, credential regeneration, publication, or purchases were performed during this build.

## Implemented

Source milestone: `a08b2c0b8b649c0ac34d6f5c3d282ebac5b4c9bd`.

- Bounded C++ dataset parser and C ABI; rejects malformed/duplicate/missing/oversized TLVs, invalid UTF-8 and unsupported page/channel combinations. Page-0 channel mask follows raw MeshCoP MSB-first encoding.
- CLI inspect and optional pinned OpenThread Commissioner read-only probe. Credentials enter via stdin; reports omit Network Key, PSKc and raw datasets.
- Probe uses Connect plus Active/Pending GET only; no Petition/SET/network-sync path. Nonzero error/partial/mismatch exits; POSIX 30-second process deadline and generic exception handling.
- Flutter three-step synthetic assessment with target selection, masked import, safe fixture, explicit unknowns, disabled join, and redacted report preview.
- Native Dart parser adapter and a real FFI smoke tool. It is not presented as live discovery in the app.
- Generated platform projects for Mac/Windows/Android/iOS plus web preview. Project-local Flutter SDK installed and checksum verified; no full Xcode installed.

## Verification

- Native Debug and Release CTests passed. Tests use always-on checks, including independent raw-wire channel mask fixtures.
- Optional Commissioner build passed against pinned source `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae`.
- Dart FFI smoke passed against the actual macOS shared library: accepted synthetic dataset metadata, rejected malformed input and duplicate TLV.
- Flutter analysis passed with no issues; 7 widget tests passed, including compact mobile viewport and synthetic labeling when a native inspector is injected.
- Flutter release web build passed. It emitted a Cupertino font-family warning; the inspected UI uses Material icons and rendered normally.
- In-app browser visual check passed for target selection and review; join control visibly disabled. Local screenshot: build/evidence/preview-review.png (ignored build artifact).
- One authorized live Eero read at 14:30 UTC returned the built-in timeout (exit 124). Authentication, current dataset, and pending state remain unknown from this attempt. No key material was logged. The subsequent firewall UI inspection could not proceed because the Mac was locked. Do not attribute the timeout to the firewall as an established cause.

## Running preview and reproducibility

Development preview: http://127.0.0.1:5187/ served on loopback only from app/build/web. It uses fictional networks and cannot migrate anything. Restart with `python3 -m http.server 5187 --bind 127.0.0.1 --directory app/build/web` if needed.

Build instructions: README.md. Root build output is build/native; optional-probe evidence was built in a temporary directory and must be rebuilt for later use. The SDK is ignored at .tooling/flutter. No remote Git repository exists.

## Next work and gates

1. Implement real native discovery and bind authenticated results into the app, keeping advertised identity provisional until read.
2. Complete a successful live read after checking endpoint/interface/firewall permission; the timed-out attempt is not compatibility proof.
3. Native Mac/iPhone packaging needs full Xcode. This Mac has Command Line Tools only. Windows and phone builds/runtime tests remain unverified.
4. Add supported credential providers; Apple entitlement and actual Google/Nest command support remain unresolved. HA stays optional.
5. Validate joining on a controlled empty/new source network before adding mutating application commands. Existing accessory transfer can remain unsupported with an explicit explanation; never reset devices automatically.
6. Review dependency versions/licenses, complete release notices, choose project license, and arrange signing before publication.

Known limits: UI is a synthetic development preview; native adapter is exercised through the tool, not integrated live discovery. Native parser validation is not complete Thread policy validation or permission to migrate. IPv6 zone identifiers unsupported by the initial CLI. Router restart persistence and universal vendor behavior have not been verified.
