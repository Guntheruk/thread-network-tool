# Thread Network Tool

A local application for understanding Thread networks and joining compatible border routers to a chosen existing network.

**Initial development build.** The C++ engine performs dataset inspection, macOS DNS-SD discovery, and optional authenticated read-only probes. The Flutter interface can show discovered routers and verified reads. A direct native desktop adapter and a loopback web development preview share the same session logic. Native application packaging is not yet validated; no joining command exists. Automatic accessory transfer is optional for the first release; Home Assistant and AI are not required by the core.

## Run the interface

With Flutter 3.47.8 available:

```sh
cd app
flutter pub get
flutter test
flutter run -d chrome
```

Without a local live session, the web interface shows an explicitly labelled synthetic demo. Mac, Windows, Android, and iOS project files are present. Native packaging needs each platform's toolchain; native phone and Windows networking remain unsupported in this build.

## Live development preview on macOS

Build the optional probe below, then build the web assets and run the local helper:

```sh
cd app
flutter build web --release --no-web-resources-cdn
dart run tool/local_server.dart \
  --engine "$PWD/../build/probe/thread-network" \
  --web-root "$PWD/build/web" \
  --session-file "$PWD/../build/live-session.json"
```

Open the private URL in the session file. The helper binds only to `127.0.0.1:5188`; the URL fragment contains a temporary access token, not Thread credentials. Treat the URL and session file as private. The file is published with owner-only permissions and is never overwritten. Use a new filename for a new session. Closing the helper invalidates that session.

Choose **Refresh discovery**, import an authorized operational dataset, then **Read this router** on one discovered router. The helper retains credentials only in process memory and passes them to the native engine through stdin. The preview distinguishes advertisements, authenticated reads, identity mismatches and failures. It cannot change networks. A new discovery clears earlier reads, and endpoint handles expire after five minutes. See [the live-read contract](docs/LIVE-READ-CONTRACT.md).

For an existing trusted credential provider, `--credential-stdin` imports one dataset line before startup. This is optional; the app does not require Home Assistant. `--discovery-engine` can select a separate discovery executable during development, for example while retaining an already-approved probe executable's firewall rule.

## Native desktop path

On macOS, Flutter calls the same session and subprocess adapter directly, without a browser or HTTP server. During native development:

```sh
cd app
flutter run -d macos \
  --dart-define=TNT_ENGINE_PATH="$PWD/../build/probe/thread-network"
```

The bundle lookup is `Contents/Helpers/thread-network`, with its core library in `Contents/Frameworks`. The [macOS packaging workflow](docs/MACOS-BUILD.md) builds a universal native helper, bundles it with Flutter, and applies a local ad hoc signature or an explicitly selected Developer ID identity. Helper relocation and local signature checks are tested; the complete Flutter package and native window remain unverified because the current development Mac has Command Line Tools rather than full Xcode.

A missing helper is shown as unavailable; it does not silently become demo data. Windows and phone launch paths explicitly report unsupported until their native integrations are implemented. Developer ID signing and notarization are separate distribution gates.

## Build the native parser

Requires a C++17 compiler and CMake. No OpenThread dependency is needed for inspection.

```sh
cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native
ctest --test-dir build/native --output-on-failure
```

`thread-network inspect` reads exactly one dataset hex line from piped standard input. It prints validated metadata, never Network Key, PSKc, or raw dataset bytes. The initial parser supports page 0, channels 11–26; an accepted dataset is not proof of router access or migration compatibility.

`thread-network capabilities` reports this executable's compiled inspection, discovery and authenticated-probe support without reading stdin or using the network. It also explicitly reports `network_writes: false`.

Test Dart calling the actual native library on macOS:

```sh
cd app
dart run tool/ffi_smoke.dart ../build/native/libthread_network_core.dylib
```

That test uses synthetic data and no network access. The live desktop flow separately invokes the bounded native executable through a direct Dart adapter.

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

`thread-network discover` needs no credential input. On macOS it browses `_meshcop._udp.local` for seven seconds, with an eight-second process deadline. Its bounded output contains allowlisted advertised metadata and resolved endpoints, not authentication proof. Other platforms return unsupported.

Run helper regression checks with `dart run tool/local_server_test.dart` from `app`. These use synthetic data and loopback connections only. The optional `tool/direct_live_smoke.dart` exercises discovery, credential import and one selected authenticated read through the direct native Flutter adapter; it requires explicit authorized real credentials through stdin and is not part of unattended unit tests.

## Scope and progress

- [Current build scope](docs/BUILD-SCOPE.md)
- [Engine contract](docs/ENGINE-CONTRACT.md)
- [Accessory-transfer assessment](docs/DEVICE-TRANSFER-ASSESSMENT.md)
- [Progress and evidence](PROGRESS.md)

No remote repository or release has been published. Project licensing and platform-provider distribution requirements will be finalized before publication.
