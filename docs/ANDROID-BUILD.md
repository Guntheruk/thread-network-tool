# Android preferred Thread credential bridge

## Scope and API

This path uses the Google Play services **Thread Network SDK**, not the Google
Home APIs. It does not require a Google Home account or Home Assistant.
`ThreadNetwork.getNetworkClient(activity).getPreferredCredentials()` returns
an `IntentSenderResult`. A null sender means no preferred credential is stored.
For a non-null sender, the app opens Google's consent activity only after the
person chooses to fetch. On approval,
`ThreadNetworkCredentials.fromIntentSenderResultData(intent)` supplies the
active operational dataset. A preferred network is a phone-selected source;
the UI must not assume it is the intended join target.

The pinned Android dependency is
`com.google.android.gms:play-services-threadnetwork:16.3.0`. Google lists it
for phone and tablet and records `getNetworkClient` as the replacement for
deprecated `getClient`. The bridge does not call `addCredentials`, remove,
router migration, or any Home API command.

The official Google Maven 16.3.0 AAR (SHA-256
`6f84ec9a9612327148b759834fa8bb3cd929c687e13d313d59124119bca5c48f`)
was inspected as a classfile on 25 October 2026. It contains the exact
`getNetworkClient(Activity)`, `getPreferredCredentials()`,
`IntentSenderResult.getIntentSender()`,
`fromIntentSenderResultData(Intent)`, and
`getActiveOperationalDataset()` signatures used here, plus the referenced
Thread Network status constants. The common status constants are documented
by [Google Play services](https://developers.google.com/android/reference/com/google/android/gms/common/api/CommonStatusCodes).

Primary references:

- [Thread Network SDK](https://developers.home.google.com/thread)
- [ThreadNetworkClient](https://developers.home.google.com/reference/com/google/android/gms/threadnetwork/ThreadNetworkClient)
- [ThreadNetworkCredentials](https://developers.home.google.com/reference/com/google/android/gms/threadnetwork/ThreadNetworkCredentials)
- [ThreadNetwork entry point](https://developers.home.google.com/reference/com/google/android/gms/threadnetwork/ThreadNetwork)
- [Google Play services versions](https://developers.google.com/android/guides/setup)

## Flutter contract

`AndroidCredentials` in `app/lib/android_credentials.dart` exposes
`availability()`, `fetchPreferred()`, and `cancelPending()`. `availability()` checks only Google
Play services readiness; `available` there does **not** prove that a preferred
credential exists. `fetchPreferred()` is the only call that reads credentials
and may show consent. It must be called from an explicit button action, not
startup or discovery. It returns `datasetHex` only with a valid `available`
result after approval. Pass that dataset to the existing validator before use;
the bridge's length check is not full dataset validation.

The `AndroidCredentialStatus` values are `available`, `unavailable`,
`missingSdk`, `notConfigured`, `localNetworkDisconnected`,
`permissionDenied`, `cancelled`, `busy`, `timedOut`, and `failure`.
`missingSdk` includes missing, disabled, or outdated Google Play services.
`notConfigured` means Google's preferred credential query returned no sender.
`localNetworkDisconnected` reflects the SDK's local Wi-Fi or Ethernet
requirement. Native failures use fixed codes; no exception message, secret,
or SDK object is logged or returned. One fetch can be pending at a time.
The native call has a 45-second deadline; Dart has a 50-second deadline.
The Dart timeout sends a matching operation ID to `cancelPending`; an explicit
UI cancellation does the same and resolves the local future immediately.
Native cancellation invalidates the active generation. Late task callbacks
and activity results are ignored, including when a new fetch has started.

## Verification status

The Android debug build check in `.github/workflows/android-build.yml` runs on
Ubuntu 24.04 with Flutter 3.47.8 and Temurin Java 17. It resolves the locked
Flutter packages, compiles `app-debug.apk`, and checks that the APK is nonempty.
It requests read-only repository permissions and has a 60-minute deadline.
It neither signs a release package nor uploads the APK. The generated project
pins Android Gradle plugin 9.1.0 and Gradle 9.3.1; Flutter supplies missing
wrapper scripts/JAR during the build without replacing the checked-in wrapper
properties. A passing hosted run will establish compilation and debug APK
packaging for its exact source SHA, including Kotlin bridge compilation. The
check must run before that result can be claimed.

The first hosted Android run, `40221044175` at `0016ea7`, reached
`:app:checkDebugAarMetadata` and found that the pinned Thread Network SDK
requires core library desugaring. The app module now enables it and pins
`com.android.tools:desugar_jdk_libs:2.0.3`, using the
[Android Gradle configuration](https://developer.android.com/studio/write/java8-support)
documented for AGP 7.4 and newer. A new hosted run is required to establish
whether Kotlin compilation and APK packaging pass; the first run did not.

The Dart channel contract can be tested with
`cd app && ../.tooling/flutter/bin/flutter test test/android_credentials_test.dart`.
This uses mock channel responses and does not establish device support.

On this Mac, `~/Library/Android/sdk`, `/Applications/Android Studio.app`, and
a usable JDK were absent at inspection. The small pinned AAR was inspected,
but Android source has not been compiled or packaged. Before claiming Android support, build on a
host with the Android SDK, Google Maven access, and a configured Flutter
toolchain, then test an Android 8.0+ phone with current Google Play services.
Test consent approval, cancellation, no preferred credential, no local
network, service missing/outdated, timeout, and restart while consent is open.
Record the exact APK build and device results separately from the mock tests.
