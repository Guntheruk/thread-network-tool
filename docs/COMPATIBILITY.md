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
| Apple credential access (macOS) | Unavailable in the local build | The framework/bridge compiles, but Apple's entitlement availability and Xcode capability catalog omit native macOS. A signing certificate alone does not establish a supported provisioning route. Guided import remains available; see `APPLE-ACCESS.md`. |
| Android preferred credentials | Bridge and debug APK build verified | At `c60c5b4`, hosted run `40224904977` compiled the Kotlin/Flutter bridge and produced a nonempty debug APK with Thread SDK 16.3.0, desugaring 2.1.3 and minimum API 26. Installation, launch, consent and credential retrieval remain unverified on a device. |
| Google Home / Nest device commands | Documented route only | Capability reads and temporary credential-sharing/join commands are described in `GOOGLE-HOME.md`; no Google account bridge, Home API implementation, Google device approval or verified Nest model exists. |
| Windows | Desktop build verified; networking unavailable | At `6498a9e`, hosted run `40220629150` passed the native core checks and Flutter Windows desktop build. Discovery and authenticated router communication remain unavailable; no Windows device runtime check is recorded. |
| iOS saved credentials | Bridge implemented; unsigned build verified | Explicit-consent provider and Flutter routing compile in the complete Runner, including the enabled physical-device branch. Default/simulator builds report access not configured. Development provisioning, device installation and real consent/retrieval remain unverified. Native phone discovery and secure phone-to-Mac transfer are separate unfinished work. |
| Home Assistant credentials | Optional desktop importer implemented | Real loopback WebSocket/TLS and role-bound UI tests pass; independent review verified the repaired TLS transport. Actual household-server compatibility remains unverified. Uses an existing installation and its saved datasets. |
| AI | Unused by core | No AI service or account is required by the app. |
| Mac internal Thread radio | Separate experimental probe; not integrated | An ordinary-user Skywalk/Spinel probe received version and capability replies on an M3 Pro Mac with macOS 27.0.1. This proves coprocessor access, not RF reception, app-sandbox support or a replacement for border-router networking. See `MAC-RADIO-RESEARCH.md`. |

## What the evidence covers

The source contains a bounded dataset parser and read-only authenticated-probe
path. A direct adapter read succeeded once against one router. The packaged Mac
app has separate evidence for local discovery and synthetic dataset handling,
not for that authenticated probe. No mutation command is enabled, and no
controlled join/recovery result is recorded for the application. The original
CLI simulation in `PROTOCOL-LAB.md` and subsequent real native Commissioner
lab in `NETWORK-MOVE-ADAPTER.md` have distinct evidence. The latter completed
three isolated software-network moves, including lost-result recovery. Neither
establishes the full application screen workflow or a supported vendor combination.

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
- `ANDROID-BUILD.md`: bridge contract, hosted APK build and remaining device gates.
- [Windows PR #4](https://github.com/Guntheruk/thread-network-tool/pull/4):
  desktop build evidence and networking limits.
- `MAC-RADIO-RESEARCH.md`: direct radio-access experiment and integration limits.
- `GOOGLE-HOME.md`: documented routes and absent Google implementation.
- `RELEASE-PLAN.md`: acceptance evidence required before broader claims.
