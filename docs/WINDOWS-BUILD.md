# Windows build evidence

The Windows GitHub workflow builds the C++ parser/core and the generated Flutter
Windows desktop project on `windows-2022`. It uses the same pinned checkout and
Flutter setup actions and Flutter 3.47.8 as the existing checks. The token has
read-only repository access, and no build output is uploaded or published.

## Reproduce the CI checks

Run these commands from the repository root on Windows with Visual Studio 2022
and its C++ desktop tools, CMake, and Flutter 3.47.8 installed:

```powershell
cmake -S . -B build/ci-native -G "Visual Studio 17 2022" -A x64 -DTNT_WITH_COMMISSIONER=OFF -DTNT_BUILD_TESTS=ON
cmake --build build/ci-native --config Release --parallel 2
ctest --test-dir build/ci-native -C Release --output-on-failure --timeout 60
cd app
flutter pub get
flutter build windows --release
```

The explicit `--config Release` and `-C Release` select the same configuration
for the Visual Studio multi-configuration generator. Commissioner support is
off, so these checks do not attempt a Windows authenticated probe.

## What a passing build establishes

A green native job establishes that the parser/core compiles and its synthetic
CTest suite passes on the hosted Windows runner. A green Flutter job establishes
that the desktop project produces a Windows release build there. Neither job
launches the app, checks its UI on a Windows desktop, or exercises a real Thread
network. Windows discovery and authenticated reads currently report unsupported;
the generated Windows project and a successful build do not establish native
networking or device compatibility. A Windows runtime check of app launch,
synthetic import/error handling, and explicit unsupported behavior remains
needed before claiming a usable Windows desktop experience.
