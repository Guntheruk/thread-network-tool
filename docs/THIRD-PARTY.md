# Third-party provenance

Initial protocol baseline: OpenThread Commissioner commit `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae`, BSD-3-Clause, https://github.com/openthread/ot-commissioner . We link upstream code only in the optional probe; no upstream source edits are required by this build. The earlier private migration patch is not needed for these metadata-only reads.

Build workarounds for the pinned source: disable unused commercial commissioning support and CLI/tests; remove the Debug fmt archive suffix expected incorrectly by the upstream CMake; demote a newer AppleClang uninitialized-const-pointer warning in upstream mbedx509. These are build compatibility measures, not a dependency security review.

Relevant transitive libraries: libevent (BSD-3-Clause), fmt (MIT), and Mbed TLS (the inspected pinned source offers Apache-2.0 OR GPL-2.0-or-later). A final linked-library inventory, version review, license selection, and notices are required before distributing binaries.

UI/toolchain used for this initial build: Flutter 3.47.8, framework revision `737ba8f885dc774b53b442759999a312c9461e4e`, Dart 3.13.7. The macOS arm64 SDK archive SHA-256 was verified against the official release manifest: `6114edc2dae3636cfefb7e4456a4510399ee856e324149b34dbacb509e329d05`. Flutter framework is BSD-3-Clause; engine/bundled dependencies have their own notices. App Dart dependencies are pinned in app/pubspec.lock; ffi 2.2.0 is BSD-3-Clause.

Apple ThreadNetwork and Google Home/Play services integrations are planned, not included. Their SDK access and distribution terms are distinct from open-source sample licenses.
