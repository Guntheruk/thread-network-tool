# Apple saved Thread credentials

Checked 25 October 2026 against Xcode 27.1 (27A9275), iPhoneOS 27.1
SDK headers, the installed capability catalog and Apple's current documentation.
This implements an iPhone credential-provider bridge. It does not implement a
secure iPhone-to-Mac transfer or finish the phone's discovery/read workflow.

## Supported development route

Apple documents the credential entitlement for iOS 15+, iPadOS 15+ and visionOS,
and allows the **Managed Thread Network Credentials (development)** capability
for development/testing. Distribution access is a separate request to Apple.
The installed catalog limits both Thread capability variants to IOS/VISION_OS
and Apple Developer Program or Enterprise Program teams. It does not list free
Personal Teams. This is published/catalog evidence, not a check of the owner's
account or a grant of access.

The bridge requires **iOS 16.4+** because the non-consenting preferred-network
availability API starts at 16.4; the retrieval API itself starts at 15.0. No
Thread radio is required by the source bridge. A physical device with credentials
available to Apple's framework, an appropriate team/profile and actual consent
remain runtime gates. Simulator builds return `accessNotConfigured`.

The default build also returns `accessNotConfigured`. iOS has no public equivalent
of the Mac's SecTask entitlement preflight; `THREAD_CREDENTIALS_ENABLED` is an
explicit developer assertion of configuration, not evidence of OS authorization.
The OS still enforces entitlement/provisioning and can reject a request.

For a future owner-configured device build:

1. Use the owner's chosen team and unique app identifier. Add Apple's development
   capability to that iOS App ID/Runner in Xcode and use its matching development
   provisioning profile, signing identity and registered physical device.
2. Use `Runner/ThreadCredentials.entitlements` as Runner's `CODE_SIGN_ENTITLEMENTS`
   and append `THREAD_CREDENTIALS_ENABLED` to Runner's
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. These are opt-in build settings; the
   checked-in project does not enable restricted entitlements by default.
3. Inspect the resulting app signature and profile for the Boolean
   `com.apple.developer.networking.manage-thread-network-credentials` entitlement.
   A source plist or successful unsigned compile does not establish access.
4. Install/launch on that device, open network setup and explicitly request saved
   credentials. Verify absent credentials, decline, success, cancellation and late
   callbacks. Confirm the returned network identity after local validation rather
   than assuming Apple's preferred network is the selected router's network.

No team login, certificate/profile creation, entitlement grant, device install,
purchase or household credential retrieval was performed in this lane. The
read-only local signing preflight found **0 valid code-signing identities**.
Do not treat App Store distribution approval as a prerequisite for merely
implementing or unsigned-compiling the development path.

## Behavior and privacy

Registration creates only a method channel. Availability never retrieves a
secret or shows the consent alert. Retrieval is reached only from the existing
explicit user action and returns the active dataset only in memory. The shared
Dart route bounds calls, accepts only nonempty datasets at most 254 bytes and
passes credentials through existing local validation. It does not log, persist,
copy to reports or put credentials into URLs.

The native availability response expires after 10 seconds and fetch after 60
seconds. Cancellation completes the caller and discards late credentials. Apple's
API exposes no cancellation method for its consent alert: the native gate retains
the prompt slot until the actual callback, including after cancellation/timeout.
A second request returns `inProgress` rather than opening overlapping prompts.
An unresolved system prompt must finish (or the app must restart) before retry.
Errors are reduced to typed generic states; platform error messages/details are
never returned. Permission denial maps only Apple's known store domain/code,
with unknown errors remaining generic failure.

## Native Mac limitation

The Mac framework/API being present or compiling does **not** establish a
provisionable native macOS credential capability. Apple's current entitlement
availability and macOS capability table omit macOS; Xcode's Thread credential
capability catalog lists only IOS/VISION_OS. Native Mac access is therefore
unsupported/unproven for this app, not something promised after a certificate
or distribution request. Keep the current safe unavailable fallback and guided
eero/Advanced import. Do not add this restricted entitlement to an ad hoc Mac
package to try to bypass provisioning. A future small iPhone companion needs a
separately designed, authenticated, encrypted transfer before it can supply the
Mac; nothing in this bridge transports credentials across devices.

## Validation

- Native request-gate host regression checks cancellation, deadlines, duplicate
  completions, prompt reservation and late/stale callback suppression using
  synthetic bytes. Run from the repository root:
  `xcrun swiftc app/ios/Runner/AppleCredentialRequest.swift tests/apple_credentials/main.swift -o /tmp/thread-apple-request-test`
  then `/tmp/thread-apple-request-test`.
- `flutter test test/apple_credentials_test.dart` from `app/` covers iOS/Mac
  platform routing, unsupported Android routing, absence of implicit fetches,
  typed errors, timeout/cancellation and bounded datasets using a mock channel.
- The enabled bridge compiled directly for arm64 iOS against real Flutter
  and ThreadNetwork headers without signing. `flutter build ios --debug
  --no-codesign` also built the complete Runner successfully (default disabled
  credential capability), including channel registration. A full Xcode Runner
  build with `THREAD_CREDENTIALS_ENABLED` and `CODE_SIGNING_ALLOWED=NO` also
  succeeded, compiling the enabled physical-device branch. Neither grants access.
- No real iPhone consent/retrieval or cross-device transfer is verified by these
  tests. Mac compilation likewise does not prove provisionable access.

## Primary references

- [Apple credential entitlement and development/distribution instructions](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.manage-thread-network-credentials)
- [Apple preferred-network retrieval and consent](https://developer.apple.com/documentation/threadnetwork/thclient/retrievepreferredcredentials(_:))
- [Managing Thread credentials and checking availability before consent](https://developer.apple.com/documentation/threadnetwork/managing-thread-network-credentials)
- [Apple supported macOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-macos)
- Installed capability evidence:
  `/Applications/Xcode.app/Contents/SharedFrameworks/DVTPortal.framework/Versions/A/Resources/DVTPortalCachedPortalCapabilities.json`,
  entries `DEV_MANAGE_THREAD_NETWORK_CREDENTIALS` and
  `MANAGE_THREAD_NETWORK_CREDENTIALS`.
