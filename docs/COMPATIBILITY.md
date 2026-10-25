# Compatibility and evidence

This is a source capability inventory, not a promise that every Thread device
or platform works. “Implemented” describes code; “verified” names the evidence
that has actually been collected. Advertisements, credential access, router
authentication, a proposed join, command acceptance and a verified outcome are
separate states. Joining remains disabled.

## Current platform and provider status

| Area | Source state | Evidence and limit |
| --- | --- | --- |
| macOS local app | Implemented | A locally signed universal app opened on Apple Silicon. Packaged-window discovery and synthetic import passed. One read against a router and the direct native adapter passed separately; neither proves authenticated reads from the packaged sandbox. Intel execution, packaged DTLS reads, Developer ID distribution signing and notarization are unverified. |
| Apple credential access (macOS) | Bridge implemented in source | The Swift/Flutter bridge has explicit consent, cancellation and typed failures. This local build lacks the credential-management entitlement and reports access unavailable; real retrieval remains unverified. Signing, entitlement and runtime access remain gates. The iOS bridge is not implemented. |
| Android preferred credentials | Bridge implemented in source | The Kotlin/Flutter bridge has bounded consent, cancellation and error states. The Android SDK/dependency have not been compiled or resolved here, and no Android device result exists. Treat Android as unverified. |
| Google Home / Nest device commands | Documented route only | Capability reads and temporary credential-sharing/join commands are described in `GOOGLE-HOME.md`; no Google account bridge, Home API implementation, Google device approval or verified Nest model exists. |
| Windows | Unavailable | The generated project is not a native networking implementation. The app reports the native read path unavailable; no Windows build or runtime check is recorded. |
| iOS | Unavailable | A generated project and documented API routes do not provide an implemented app bridge. No iOS build or runtime check is recorded. |
| Home Assistant / AI | Optional and unused by core | Neither is required by the local workflow; neither is an account or credential provider in this app. |

## What the evidence covers

The source contains a bounded dataset parser and read-only authenticated-probe
path. A direct adapter read succeeded once against one router. The packaged Mac
app has separate evidence for local discovery and synthetic dataset handling,
not for that authenticated probe. No mutation command is enabled, and no
controlled join/recovery result is recorded.

The product scopes differ by operation. Reading one vendor router is a
single-router credential/authentication check; it does not inventory or assess
every border router on a source network, establish which network should be
retained, or move accessories from an existing network. Whole-source assessment
and accessory migration need their own supported workflow and evidence. Existing
accessories are outside the initial supported join case unless a separately
tested migration path is added.

Google's Android Thread Network SDK credential route is separate from Google
Home device commands. Google Home APIs are currently research/documentation only.
The documented Google device commands have not been tested. Likewise, vendor
app instructions for copying credentials do not establish vendor router-command
support.

## Evidence references

- `PROGRESS.md`: implementation, local verification, one direct-adapter router
  read, packaged Mac verification and outstanding gates.
- `MACOS-BUILD.md`: packaged-app build and its explicitly unverified paths.
- `ANDROID-BUILD.md`: implemented bridge contract and uncompiled status.
- `GOOGLE-HOME.md`: documented routes and absent Google implementation.
- `RELEASE-PLAN.md`: acceptance evidence required before broader claims.
