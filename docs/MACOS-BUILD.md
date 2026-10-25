# macOS native app packaging

This builds a local macOS Flutter app with the read-only native helper. It does
not publish or notarize. Building alone does not establish runtime support;
the separate native-window checks below record the current evidence.

## Prerequisites

- Full Xcode selected as the active developer directory (`xcode-select -p`)
  or supplied for this command through `DEVELOPER_DIR`,
  with a working `xcodebuild` and macOS SDK. Command Line Tools alone are
  enough for the relocation smoke test, but not the Flutter macOS build.
- A Flutter SDK that supports this project, supplied by `TNT_FLUTTER_BIN` or
  installed at `.tooling/flutter/bin/flutter`.
- CMake, supplied by `TNT_CMAKE_BIN` or available on `PATH`.
- A clean checkout of OpenThread Commissioner at the commit required by the
  root CMake file. Set `TNT_COMMISSIONER_SOURCE` to that checkout. The build
  script requires the optional authenticated probe and confirms the resulting
  helper reports `authenticated_probe: true` and `network_writes: false`.

The script does not change the selected Xcode installation, accept licenses,
install software, fetch upstream source, or make home-network calls.

## Local build

```sh
TNT_CMAKE_BIN=/absolute/path/to/cmake \
TNT_FLUTTER_BIN=/absolute/path/to/flutter \
TNT_COMMISSIONER_SOURCE=/absolute/path/to/ot-commissioner \
tools/build_macos_app.sh
```

The default result is a local ad hoc signed app in `build/macos-package/`.
The script refuses to overwrite a prior package; set `TNT_OUTPUT_DIR` to a
fresh directory for another run. `TNT_NATIVE_BUILD_DIR` sets the native build
directory. Native code targets macOS 12.0 and builds `arm64;x86_64` by
default to match Flutter's universal release output. If Flutter is explicitly
configured for one architecture, `TNT_MACOS_ARCHITECTURES` can set the native
CMake architecture list. The script checks that the helper covers every app
executable architecture before packaging.

For a Developer ID signing attempt, set `TNT_SIGN_MODE=developer-id` and
`TNT_SIGN_IDENTITY` to an installed **Developer ID Application** identity.
The script signs nested libraries and frameworks, then the helper with only
the sandbox and inherit entitlements, then the outer app. It verifies the
resulting signatures recursively. Developer ID signing requests a secure
timestamp and Hardened Runtime on each signed code item. A Developer ID signature is not notarization or
distribution approval. Local ad hoc signatures are only for local validation.

The parent app retains App Sandbox and grants both network client and server
permissions. [Apple's UDP entitlement rules](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)
require receive access as well as send access for the helper's DTLS exchanges.
The helper inherits these permissions from its parent. The app also declares
its local-network purpose and `_meshcop._udp` Bonjour service in its Info.plist.

The installed helper is `Contents/Helpers/thread-network`; its core library
is `Contents/Frameworks/libthread_network_core.dylib`. The helper loads the
core through `@executable_path/../Frameworks`; the core install ID is
`@rpath/libthread_network_core.dylib`. The packaging script rejects source
or build paths in those native dependencies and rejects unbundled non-system
dynamic libraries.

## Verification available with Command Line Tools

```sh
TNT_CMAKE_BIN=/absolute/path/to/cmake tools/test_macos_bundle.sh
```

This creates an isolated, ignored test directory under
`build/packaging-tests/`. It builds the core-only helper, installs it in a
synthetic app with a universal helper, moves that app, deletes its test build tree, and runs synthetic
valid and invalid dataset inspections from `/`. It also builds a separate
synthetic app, signs its nested native code with the local ad hoc identity,
checks the sandbox-inheritance entitlements, and verifies the signatures.
Its signed parent then launches the inherited helper for valid and invalid
synthetic inspections. This verifies the native sandbox inheritance path.
The packaged-app checks below add native Flutter launch and sandboxed discovery;
authenticated DTLS reads from that app remain unverified.

Run this test from a normal macOS shell. In this development environment,
running inside Codex's process sandbox aborts the signed synthetic parent
before `main`; the same test passes outside that enclosing sandbox. The
test deliberately fails on that condition instead of skipping signed execution.

No test invokes discovery or probe against a home device. The full app build
uses the pinned Commissioner source but does not perform a network read.

## Packaged application verification — 25 October 2026

Source `dfa41386139710a63ed81fdcaa1c75c9272bda31` built successfully with
Xcode 27.1 (27A9275), Flutter 3.47.8 and the pinned Commissioner source.
`DEVELOPER_DIR` selected Xcode for the build without changing the system default.
Both the app executable and helper contain `arm64` and `x86_64` slices.
Recursive strict signature verification passed with the local ad hoc identity;
the parent retains App Sandbox and the helper retains sandbox inheritance.

On the development Apple Silicon Mac:

- The packaged app opened a native Flutter window with the live read-only view.
- Bounded discovery completed with eight unverified router advertisements,
  both before and after restarting the app.
  Process inspection confirmed the app launched its bundled helper, which exited
  after the scan. No browser or HTTP helper handled this request.
- The native import dialog accepted a synthetic dataset and rejected malformed
  input with a generic error and cleared input. No household credentials were
  imported, and no router probe or network change was attempted.
- The report showed discovery counts and zero authenticated reads while excluding
  network names, device identities, endpoints and credentials.
- Quitting and reopening the app returned to the initial state without imported
  credentials or discovery results.

Authenticated reads from the packaged sandbox, Intel execution, Developer ID
signing and notarization remain unverified. Earlier direct Dart-adapter reads
are separate evidence, not proof of the packaged app's DTLS path. Build logs and
screenshots remain ignored local artifacts; do not publish household screenshots.
