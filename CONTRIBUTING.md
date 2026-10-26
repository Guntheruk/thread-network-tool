# Contributing

Thanks for helping develop Thread Network Tool. This is a developer alpha: default packages are read-only; the separately enabled Mac alpha can change an entire empty source Thread network. No retail Eero model and firmware combination has yet been verified for the packaged join and recovery flow. See [Mac alpha](docs/MAC-ALPHA.md) and [the developer preview](docs/CONTRIBUTOR-PREVIEW.md).

## Get started

For the synthetic interface, install Flutter 3.47.8 and run from a clone:

```sh
cd app
flutter pub get
flutter test
flutter run -d chrome
```

Without a live session, the browser shows a labelled synthetic demo. To build and test the native parser, run from the repository root with CMake and a C++17 compiler:

```sh
cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native
ctest --test-dir build/native --output-on-failure
```

See the [README](README.md#local-verification) for the broader local synthetic checks and [Mac packaging](docs/MACOS-BUILD.md) for prerequisites. No contributor licence agreement, account signup beyond the hosting service needed to submit a change, or analytics signup is required by this project.

## Make a contribution

1. Open an issue to describe a bug or proposed work, or choose an existing issue. Small fixes can go straight to a pull request.
2. Make a focused change with synthetic fixtures and disposable peers. Explain the problem, the change and the checks you ran in your pull request. Identify checks you could not run.
3. Respond to review and update the pull request. Hosted workflows are manual; a submitted pull request does not itself establish that CI ran.

Useful areas include the [simulator counter fix](docs/SIMULATOR-COUNTER-FIX.md) and coverage beyond its tested configuration; clean Mac installation and trusted distribution; Apple credential provisioning and consent; and native platform networking. Help with a specifically identified **spare Eero model and firmware** on an isolated, empty source network is welcome for planning controlled acceptance and recovery. Coordinate an explicit test plan before operating real equipment; never use a working household as the test network.

The optional Mac alpha changes the whole source network, needs complete credentials for both networks, and does not migrate accessories or offer automatic rollback. Discovery cannot prove a network is empty or list every router. General household pilot readiness is separate from developer contributions; see [pilot gates](docs/PILOT.md).

## Reports and privacy

Use synthetic data in examples. Do not post operational datasets, keys, tokens, addresses, household or network names, device identities, private recovery files, or raw household logs. Review screenshots and redacted reports before sharing. For an uncertain network change, stop and preserve the result; do not retry or reset devices. See the [tester quickstart](docs/MAC-ALPHA-TESTER.md).
