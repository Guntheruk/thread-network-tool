# Thread Network Tool

A local application for understanding Thread networks and joining compatible border routers to a chosen existing network.

**Developer alpha — v0.1.0-alpha.1.** Default packages inspect credentials, discover routers and perform authenticated reads. The explicit [Mac Eero alpha](docs/MAC-ALPHA.md) also includes the real source-network join worker, confirmation and recovery flow. It requires an empty source network and complete credentials for both networks, using guided eero copying, existing Home Assistant or Advanced input. Automatic Apple credential retrieval is outside this alpha. Physical/vendor compatibility remains unverified for this packaged app. A separate Linux profile exercises guarded moves against isolated software routers. Home Assistant and AI are not required by the core.

## Try it or contribute

[Developer alpha release and Mac download](https://github.com/Guntheruk/thread-network-tool/releases/tag/v0.1.0-alpha.1)
· [Contributing](CONTRIBUTING.md)
· [Offer help or report a problem](https://github.com/Guntheruk/thread-network-tool/issues/new/choose)

The Mac download is locally ad hoc signed. Developer ID signing, notarization,
clean-Mac installation and retail Eero acceptance remain open contribution areas.
Use synthetic fixtures or a coordinated isolated setup with spare equipment.
[The developer preview](docs/CONTRIBUTOR-PREVIEW.md) explains the available paths.

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

Choose **Find routers**, then **Set up network access**. The guided eero route explains how to copy its Active operational dataset; manual entry is under Advanced. Apple saved-credential access is implemented as an iOS bridge, with provisioning and device testing still required; native Mac provisioning is unproven. See [credential routes and the optional phone companion](docs/CREDENTIAL-ACCESS.md). After setup, use **Check** to verify a router. Credentials stay in process memory and reach the native engine through stdin. Advertisements, authenticated reads and failures remain distinct. This preview cannot change networks. A new discovery clears earlier reads; endpoint handles expire after five minutes. See [the live-read contract](docs/LIVE-READ-CONTRACT.md).

For an existing trusted credential provider, `--credential-stdin` imports one dataset line before startup. This is optional; the app does not require Home Assistant. `--discovery-engine` can select a separate discovery executable during development, for example while retaining an already-approved probe executable's firewall rule.

## Native desktop path

On macOS, Flutter calls the same session and subprocess adapter directly, without a browser or HTTP server. During native development:

```sh
cd app
flutter run -d macos \
  --dart-define=TNT_ENGINE_PATH="$PWD/../build/probe/thread-network"
```

The bundle lookup is `Contents/Helpers/thread-network`, with its core library in `Contents/Frameworks`. The [macOS packaging workflow](docs/MACOS-BUILD.md) builds universal native helpers, bundles them with Flutter, and applies a local ad hoc signature or an explicitly selected Developer ID identity. Set `TNT_MAC_ALPHA=1` for the additional move worker and durable journal. Signed Flutter test packages have completed authenticated DTLS reads and source-only SET operations against isolated synthetic peers. The normal production window exposes the join flow; actual Eero firmware acceptance, Intel execution and trusted distribution remain separate checks. See [current alpha evidence and limits](docs/MAC-ALPHA.md).

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
python3 tools/prepare_commissioner_source.py \
  --source vendor/ot-commissioner --output build/commissioner-source
cmake -S . -B build/probe -DCMAKE_BUILD_TYPE=Release \
  -DTNT_WITH_COMMISSIONER=ON \
  -DTNT_COMMISSIONER_SOURCE="$PWD/build/commissioner-source"
cmake --build build/probe
```

Preparation needs Python with `tarfile.data_filter` (3.12+ or a patched interpreter).
Use a fresh generated output directory. CMake verifies the committed patch/tree identity.
The fetch helper refuses unexpected or modified inputs. See [third-party notes](docs/THIRD-PARTY.md).

`thread-network probe <numeric-ip> <port>` accepts one dataset line through stdin. It establishes DTLS and requests active metadata and pending status only. It never petitions, enables joiners, syncs network data, or sends a dataset SET. Check both process exit status and structured output. The POSIX CLI has a 30-second process deadline; callers should also use a bounded wait. IPv6 addresses requiring an interface-zone suffix are not yet supported by this CLI.

Probe builds have been tested on macOS only. Windows probe builds deliberately report unsupported rather than implying that compiling the parser establishes Windows networking support. This general probe and default package contain no network-changing command; the [explicit Mac alpha](docs/MAC-ALPHA.md) uses a separate worker.

`thread-network discover` needs no credential input. On macOS it browses `_meshcop._udp.local` for seven seconds, with an eight-second process deadline. Its bounded output contains allowlisted advertised metadata and resolved endpoints, not authentication proof. Other platforms return unsupported.

Run helper regression checks with `dart run tool/local_server_test.dart` from `app`. These use synthetic data and loopback connections only. The optional `tool/direct_live_smoke.dart` exercises discovery, credential import and one selected authenticated read through the direct native Flutter adapter; it requires explicit authorized real credentials through stdin and is not part of unattended unit tests.

## Scope and progress

- [Mac alpha tester quickstart](docs/MAC-ALPHA-TESTER.md)
- [Developer contributor preview](docs/CONTRIBUTOR-PREVIEW.md)
- [Simulator connectivity repair and reproduction](docs/SIMULATOR-COUNTER-FIX.md)
- [Current build scope](docs/BUILD-SCOPE.md)
- [First-release completion plan](docs/RELEASE-PLAN.md)
- [Compatibility and evidence](docs/COMPATIBILITY.md)
- [Candidate pilot gates](docs/PILOT.md)
- [Engine contract](docs/ENGINE-CONTRACT.md)
- [Accessory-transfer assessment](docs/DEVICE-TRANSFER-ASSESSMENT.md)
- [Google Home research and integration route](docs/GOOGLE-HOME.md)
- [Interface direction](docs/INTERFACE.md)
- [Proposed migration beta](docs/MIGRATION-BETA.md)
- [Synthetic join assessment and recovery](docs/JOIN-LAB.md)
- [Isolated OpenThread network-move lab](docs/PROTOCOL-LAB.md)
- [Next source-network review implementation](docs/NETWORK-MOVE-PLAN.md)
- [Android credential bridge and build limits](docs/ANDROID-BUILD.md)
- [Dependency notice inventory](docs/DEPENDENCY-INVENTORY.md)
- [Progress and evidence](PROGRESS.md)

Source, issues and pull requests are in the [GitHub repository](https://github.com/Guntheruk/thread-network-tool).
Hosted build/test workflows remain manual to avoid automatic GitHub Actions
usage on PR updates. Codex code review is separate.

## Licence

Original project code and documentation use [Apache 2.0](LICENSE).
Third-party components retain their own licences; the selected release terms
and notice locations are in [Licensing](docs/LICENSING.md).

## Local verification

On macOS or Linux with the installed toolchains, run `tools/check_local.sh`.
Set `TNT_CMAKE_BIN` and `TNT_FLUTTER_BIN` if they are not at the default paths.
An optional `TNT_COMMISSIONER_SOURCE` enables the verified native dependency;
otherwise the script builds the parser and private journal only. The script runs
native, tooling, Flutter and recovery checks using synthetic data and loopback
servers. It performs no household discovery or router operation. The real
[isolated app workflow](docs/NETWORK-MOVE-APP-INTEGRATION.md), platform builds and
device/provider tests remain separate evidence.
