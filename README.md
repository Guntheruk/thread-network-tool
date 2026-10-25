# Thread Network Tool

A local application for understanding Thread networks and joining compatible border routers to a chosen existing network.

**Initial development build.** The C++ engine performs dataset inspection and optional authenticated read-only probes. The Flutter interface currently uses clearly labelled synthetic networks. It does not discover your LAN or join routers yet. Automatic accessory transfer is optional for the first release; Home Assistant and AI are not required by the core.

## Run the interface

With Flutter 3.47.8 available:

```sh
cd app
flutter pub get
flutter test
flutter run -d chrome
```

The web interface is a development preview, not a browser-based Thread engine. Mac, Windows, Android, and iOS project files are present. Native packaging needs each platform's toolchain; native phone and Windows runtime support have not been verified.

## Build the native parser

Requires a C++17 compiler and CMake. No OpenThread dependency is needed for inspection.

```sh
cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native
ctest --test-dir build/native --output-on-failure
```

`thread-network inspect` reads exactly one dataset hex line from piped standard input. It prints validated metadata, never Network Key, PSKc, or raw dataset bytes. The initial parser supports page 0, channels 11–26; an accepted dataset is not proof of router access or migration compatibility.

Test Dart calling the actual native library on macOS:

```sh
cd app
dart run tool/ffi_smoke.dart ../build/native/libthread_network_core.dylib
```

That test uses synthetic data and no network access. The native parser adapter is exercised by this tool; the UI remains a synthetic network board.

## Optional authenticated read-only probe

```sh
tools/fetch_commissioner.sh
cmake -S . -B build/probe -DCMAKE_BUILD_TYPE=Release \
  -DTNT_WITH_COMMISSIONER=ON \
  -DTNT_COMMISSIONER_SOURCE="$PWD/vendor/ot-commissioner"
cmake --build build/probe
```

CMake verifies the upstream commit. The fetch helper refuses to replace an unexpected or modified checkout. The current pinned dependencies need review before release; see [third-party notes](docs/THIRD-PARTY.md).

`thread-network probe <numeric-ip> <port>` accepts one dataset line through stdin. It establishes DTLS and requests active metadata and pending status only. It never petitions, enables joiners, syncs network data, or sends a dataset SET. Check both process exit status and structured output. The POSIX CLI has a 30-second process deadline; callers should also use a bounded wait. IPv6 addresses requiring an interface-zone suffix are not yet supported by this CLI.

Probe builds have been tested on macOS only. Windows probe builds deliberately report unsupported rather than implying that compiling the parser establishes Windows networking support. No network-changing command exists in this build.

## Scope and progress

- [Current build scope](docs/BUILD-SCOPE.md)
- [Engine contract](docs/ENGINE-CONTRACT.md)
- [Accessory-transfer assessment](docs/DEVICE-TRANSFER-ASSESSMENT.md)
- [Progress and evidence](PROGRESS.md)

No remote repository or release has been published. Project licensing and platform-provider distribution requirements will be finalized before publication.
