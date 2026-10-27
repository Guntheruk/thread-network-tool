# Contributor preview

Thread Network Tool is an experimental local application for understanding
Thread networks and, in a separately enabled Mac build, joining an empty source
network to a selected existing network. This preview is for developers working
with synthetic fixtures. It is not a general household migration pilot.

Default packages are read-only. The opt-in Mac worker changes the **whole
source Thread network**, not a single router, and does not migrate accessories.
The packaged app has no verified retail Eero join or recovery combination.
Discovery alone cannot establish that a source network is empty or identify all
its routers. Do not test changes on a working household network.

## Build and test locally

For the synthetic interface, install Flutter 3.47.8 and run:

```sh
cd app
flutter pub get
flutter test
flutter run -d chrome
```

The browser shows a labelled synthetic demo without a live session. For the
native parser, from the repository root with CMake and a C++17 compiler:

```sh
cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native
ctest --test-dir build/native --output-on-failure
```

`tools/check_local.sh` runs the documented local synthetic and loopback checks;
see the [README](../README.md#local-verification) for toolchain settings and
limits. The [Mac packaging guide](MACOS-BUILD.md) describes the local ad hoc
build, including Xcode, Flutter, CMake and pinned Commissioner prerequisites.
No paid Apple membership is required merely to share or build the source; local
ad hoc signing is distinct from Developer ID signing and notarization for a
trusted downloadable app. The opt-in worker and its requirements are described
in [Mac alpha](MAC-ALPHA.md).

## Where help is needed

- **Simulator and upstream review:** a pinned OpenThread MAC counter mismatch
  was reproduced with a native regression and repaired. The unchanged full
  app fixture now passes all seven gates, including cross-network traffic and
  recovery without redispatch. Help review the scoped correction and extend
  coverage beyond its tested single-radio configuration. See the
  [simulator repair and reproduction](SIMULATOR-COUNTER-FIX.md); keep the
  independent connectivity check intact.
- **Mac installation:** help validate a future signed and notarized exact
  candidate on a clean Mac without development tools. Local ad hoc builds do
  not establish this distribution path.
- **Isolated retail combination:** help plan controlled acceptance and recovery
  for a specifically identified spare Eero model and firmware, with an empty,
  isolated source network and no household accessories. Do not operate a real
  network without an explicit, reviewed test plan and authorization.
- **Apple credentials:** help with provisioning, consent, device testing and
  secure transfer for the existing iOS bridge; native Mac provisioning remains
  unproven. See [credential access](CREDENTIAL-ACCESS.md).
- **Windows and phones:** help implement and validate native networking and
  provider routes. Project files and credential bridges do not establish
  platform or vendor support. See [Android](ANDROID-BUILD.md) and
  [Google Home](GOOGLE-HOME.md).

Use synthetic credentials and disposable peers for development. Share concise,
sanitized results; never post datasets, keys, tokens, addresses, household
labels, device identities or raw household logs. Do not retry an uncertain
network change. The [pilot gates](PILOT.md) remain separate from this developer
preview and must be met before inviting general household participants.

Original project code is available under [Apache 2.0](../LICENSE).
[Contribution guidance](../CONTRIBUTING.md) and issue templates are available.
The owner authorized the public developer alpha on 27 October 2026; hosted
workflows remain manual and no paid cloud review is part of this release.
