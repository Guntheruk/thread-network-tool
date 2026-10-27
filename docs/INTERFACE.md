# Interface direction — 25 October 2026

Richard requested a simpler interface informed by Recursive Systems Elixir.
Reference inspected at `10f75ce1450315f39b7826aa41071bb771fdd850`:
`assets/css/app.css` and `docs/project-context/01-consulting-product-and-interface.md`.
The reference project is unchanged. This app retains its Flutter/C++ architecture.

## Visual language

- Neutral background `#faf9f8`, white surfaces, ink `#201f1e`, secondary text
  `#605e5c`, and a single interaction blue `#0f6cbd`.
- Flat bordered surfaces, 4px corners, restrained status colours and no routine
  card shadows. Clear 14px body, 16px row titles and 28px page headings.
- Compact command area, readable router rows and generous spacing between tasks.
  Touch targets remain at least 44px high; desktop density is not copied onto phones.

## Main task

Find routers → add authorized credentials → check a selected router.

The default view should show what was found, what has been checked and the next
action. Read-only scope stays visible. Thread version, endpoint state, protocol
codes and exact timestamps belong in expandable details. Reports remain secondary
and exclude credentials and household identifiers.

Advertisements are observations. A matching name does not prove a shared network.
Only a completed authenticated matching read earns a verified state. Mismatch,
timeout, partial, unsupported and not checked remain distinguishable by text and
icon, not colour alone. Network joining stays disabled and has one modest footer
control rather than repeated promotional panels.

Google Home has a documented mobile integration route but is not connected in this
build. See GOOGLE-HOME.md. Credential providers and guided vendor copying reduce
manual dataset handling; the interface must say which routes are actually available.

Verification includes narrow and desktop layouts, long names, enlarged text,
loading/error/unsupported states, detail disclosure, credential clearing, report
redaction and the disabled join control. Visual checks are separate from unit tests.

## Credential setup for ordinary users

Owner correction: asking people to find a hexadecimal dataset is not a finished
consumer setup flow. The live dialog now implements guided eero copying and an
Advanced route. The Mac Apple bridge is integrated with explicit unavailable
states; real retrieval remains gated by its entitlement and runtime verification.
The Android bridge is implemented separately but not yet wired to a usable phone
discovery/read workflow.

The primary action should be **Set up network access**. Explain that access lets
the app check the selected network and does not change it. Offer only working
routes for the current platform, with manual dataset entry under **Advanced**.

1. **Use saved credentials**, where a native provider is implemented: request OS
   consent, retrieve the available credentials, validate them internally and
   confirm the network identity. Do not assume the phone's preferred network is
   the one the user selected. An unavailable provider must not look connected.
2. **Get credentials from eero**: guide the person to Thread settings in the eero
   app, copy the field labelled **Active operational dataset**, then return and
   paste. The app validates the data without requiring the person to interpret
   hex. The separate **Thread Network Key** is insufficient. The owner's app
   screenshot on 25 October 2026 shows both the dataset field and tap-and-hold
   copying; confirm app-version differences rather than inventing a universal
   menu path. Never suggest regenerating credentials for this task.
3. If a supported route is unavailable, say whether access was declined,
   credentials were absent, permissions are missing, or the platform is not
   supported. Give a specific next step without resetting a router or device.

The iPhone bridge implements consent-based preferred-credential retrieval and
requires configured development signing plus an actual device test. The native
Mac framework compiles, but Apple's current entitlement availability and Xcode
capability catalog omit native macOS. Do not promise that signing the Mac app
alone enables saved credentials. A phone-to-Mac transfer remains separate work;
guided eero and Advanced import remain available. See `APPLE-ACCESS.md`.
[Apple credential API](https://developer.apple.com/documentation/threadnetwork/thclient/retrievepreferredcredentials(_:)),
[Apple entitlement requirements](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.manage-thread-network-credentials).

Android's Thread Network SDK provides a consent flow for stored preferred or
network-specific credentials. eero documents syncing its credentials into Apple
and Google mobile keychains. A desktop-to-phone handoff needs a separately
implemented secure transfer; it must not put credentials in a URL or report.
[Google Thread SDK](https://developers.home.google.com/thread),
[eero Thread guide](https://eero.zendesk.com/hc/en-us/articles/360000104706-What-is-Thread).

Router discovery reveals advertisements, not secret credentials. Keep provider
authorization, dataset validation and authenticated router verification as
separate internal states while presenting each next action in ordinary language.
