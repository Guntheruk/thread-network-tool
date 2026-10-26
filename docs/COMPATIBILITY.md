# Compatibility and evidence

This is a source capability inventory, not a promise that every Thread device
or platform works. “Implemented” describes code; “verified” names the evidence
that has actually been collected. Advertisements, credential access, router
authentication, a proposed join, command acceptance and a verified outcome are
separate states. Default consumer builds remain read-only with joining disabled.
The explicit [Mac Eero alpha](MAC-ALPHA.md) includes a separate source-only move
worker. Its actual signed-parent protocol tests use isolated synthetic peers;
retail compatibility is still unverified for the packaged app.

## Current platform and provider status

| Area | Source state | Evidence and limit |
| --- | --- | --- |
| macOS local app | Implemented, opt-in Eero alpha | A locally signed universal production app opens on Apple Silicon with the real join review. Signed Flutter test packages performed authenticated DTLS reads and source-only SET operations against loopback peers using bundled sandbox-inherited helpers and the private durable journal. Real Eero firmware acceptance, Intel execution, Developer ID distribution signing and notarization remain unverified. |
| Apple credential access (macOS) | Unavailable in the local build | The framework/bridge compiles, but Apple's entitlement availability and Xcode capability catalog omit native macOS. A signing certificate alone does not establish a supported provisioning route. Guided import remains available; see `APPLE-ACCESS.md`. |
| Android preferred credentials | Bridge and debug APK build verified | At `c60c5b4`, hosted run `40224904977` compiled the Kotlin/Flutter bridge and produced a nonempty debug APK with Thread SDK 16.3.0, desugaring 2.1.3 and minimum API 26. The production credential dialog does not expose an Android route, and phone discovery/read and desktop transfer are unfinished. Installation, launch, consent and credential retrieval remain unverified on a device. |
| Google Home / Nest device commands | Documented route only | Capability reads and temporary credential-sharing/join commands are described in `GOOGLE-HOME.md`; no Google account bridge, Home API implementation, Google device approval or verified Nest model exists. |
| Windows | Desktop build verified; networking unavailable | At `6498a9e`, hosted run `40220629150` passed the native core checks and Flutter Windows desktop build. Discovery and authenticated router communication remain unavailable; no Windows device runtime check is recorded. |
| iOS saved credentials | Bridge implemented; unsigned build verified | Explicit-consent provider and Flutter routing compile in the complete Runner, including the enabled physical-device branch. Default/simulator builds report access not configured. Development provisioning, device installation and real consent/retrieval remain unverified. Native phone discovery and secure phone-to-Mac transfer are separate unfinished work. |
| Home Assistant credentials | Optional desktop importer implemented | Real loopback WebSocket/TLS and role-bound UI tests pass; independent review verified the repaired TLS transport. Actual household-server compatibility remains unverified. Uses an existing installation and its saved datasets. |
| AI | Unused by core | No AI service or account is required by the app. |
| Mac internal Thread radio | Separate experimental probe; not integrated | An ordinary-user Skywalk/Spinel probe received version and capability replies on an M3 Pro Mac with macOS 27.0.1. This proves coprocessor access, not RF reception, app-sandbox support or a replacement for border-router networking. See `MAC-RADIO-RESEARCH.md`. |

## What the evidence covers

The source contains a bounded dataset parser and read-only authenticated-probe
path. A direct adapter read succeeded once against one router. Signed Mac test
packages now have separate evidence for authenticated loopback DTLS reads,
source-only SET, rejection and guards that prevent sending. Default consumer
builds expose no mutation command; `TNT_MAC_ALPHA=1` includes the dedicated
worker described in `MAC-ALPHA.md`. The original CLI simulation in `PROTOCOL-LAB.md` and subsequent native
Commissioner lab in `NETWORK-MOVE-ADAPTER.md` have distinct historical evidence;
the latter completed three isolated software-network moves.

At `a2949a68ec159bdc4b76304ef955bb028f5f097d`, the actual isolated Flutter-screen
workflow passed lost-result recovery with two real app processes, one
Petition/SET, zero restart dispatches, independent outcome verification and
secret redaction. Its separate key-change attempt reached recovery but exited
unsuccessfully; the exact assertion and final oracle flags were not retained.
The cause and physical convergence remain unknown. This mixed evidence is not
full application runtime acceptance, does not establish results for later
source heads, and establishes no supported retail-vendor combination. See
`PROGRESS.md` for the exact evidence and limits.

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
