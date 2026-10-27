# Google Home integration — research and next implementation

Reviewed 25 October 2026 against Google's Android and iOS documentation.
Google Home device control remains planned: there is no Google account connection
or verified Nest router support. A separate Android Thread Network SDK credential
bridge is implemented with consent and cancellation. Its hosted debug APK build
passed at `c60c5b4`; consent and retrieval remain unverified on a device.
The production credential dialog has no Android route; phone discovery/read
and secure desktop transfer remain unfinished. See [ANDROID-BUILD.md](ANDROID-BUILD.md).

## Documented routes

| Route | What the documentation supports | Product boundary |
| --- | --- | --- |
| Android Thread Network SDK | User-consented retrieval of preferred or network-specific credentials from Google Play services. App-owned credentials have a separate direct-access route. | Credentials alone do not establish control of a border router. [Google Thread SDK](https://developers.home.google.com/thread), [ThreadNetworkClient](https://developers.home.google.com/reference/com/google/android/gms/threadnetwork/ThreadNetworkClient) |
| Google Home APIs for Android and iOS | Read border-router capabilities; where supported, activate temporary credential sharing and request a network join. | Check each device's actual traits and commands. Do not infer Nest support from a network advertisement. [Android guide](https://developers.home.google.com/apis/android/device/border-router), [iOS guide](https://developers.home.google.com/apis/ios/device/border-router) |
| Apple Thread credentials on iOS | Apple's ThreadNetwork framework provides credential access with consent and distribution entitlement requirements. | Separate from a Google Home account connection. [Apple guide](https://developer.apple.com/documentation/threadnetwork/managing-thread-network-credentials), [Google iOS commissioning](https://developers.home.google.com/apis/ios/commissioning) |
| Mac and Windows | The Mac local discovery/read adapter is independent of a Google Home SDK; Windows networking is not implemented. | No desktop Google Home SDK route was established by this research. Mobile-assisted desktop credentials would need a separately designed secure transfer. |

Google Home access requires account authorization and consent for the chosen home
and devices. Google-made device support also has a Google consent approval gate.
See [Android permissions](https://developers.home.google.com/apis/android/permissions),
[iOS initialization](https://developers.home.google.com/apis/ios/initialize), and
[Google Home policies](https://developers.home.google.com/policies).

## Proposed user flow

1. Choose **Google Home** on a supported phone. Explain the requested access before
   opening Google's consent screen; cancellation leaves the local session usable.
2. Choose the home and see supported routers, with **Not checked** as the initial
   state. Read capabilities first. Account connection, credentials, and a verified
   router read are separate states.
3. Request credentials only when needed and with consent. Keep datasets and
   temporary sharing keys out of logs, URLs, reports and analytics. Starting a
   temporary sharing session is an explicit action, not part of passive discovery.
4. Show a proposed join only after the device command, source/target credentials
   and recovery path have been validated in a controlled lab. Confirm the specific
   router and target before any change. Existing accessories may require separate
   recovery; never reset them automatically.

Default consumer builds keep joining disabled. A future Google implementation
would need a native Kotlin/Swift bridge for consent and read-only capability
enumeration, followed by testing one actual Nest model. This remains separate
from the current Mac-first release and is not an automatic mobile scope
expansion. The shared Flutter interface can reuse the same states, but it must not display an operational Google connection before
that bridge exists. Home Assistant and AI remain optional.

Desktop clarification: Apple's public preferred-credential API is available in
the Mac framework and the bridge compiles, but that does not establish a
provisionable native macOS credential capability. Apple's recorded entitlement
availability and Xcode capability catalog omit native macOS. A signing
certificate alone does not resolve this, and a legitimate native, Catalyst or
iPad-app-on-Mac route remains unproven. Keep the safe unavailable fallback;
see [APPLE-ACCESS.md](APPLE-ACCESS.md). This is separate from Google Home APIs.
Guided eero copying and Advanced import remain available as specified in
[INTERFACE.md](INTERFACE.md).
