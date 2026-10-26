# Dependency and notice inventory

The link inventory below was recorded at source head
`422dab9b453c5b4d500c79a45bd9f65099b0d3bc`; the collector description reflects
the subsequent generated-source and Everest notice handling. This is historical
link evidence, not an inventory of the exact current package. It does not choose
a license for this project, resolve legal interpretation, or certify that a
distribution package is complete. Regenerate local notice inputs with:

```sh
python3 tools/collect_third_party_notices.py \
  --commissioner-root /absolute/path/to/verified/generated-source
```

The default output is `build/release-notices/`, which is ignored. The collector
does not fetch sources, copy whole caches, overwrite an existing output
directory, select a project license, or include local absolute paths in its
generated manifest. It reads the Commissioner source from the existing CMake
cache when available, otherwise from `vendor/ot-commissioner`; use
`--commissioner-root` when neither path applies. It records missing and
ambiguous package-license files as gaps and exits nonzero when any required
input is unavailable. Commissioner input must be a verified generated tree:
the collector checks its committed tree identity before and after collection,
records the original parent/submodule revisions from provenance, and retains the
provenance, manifest and exact patch beside the notices. An unmodified Git
checkout is not a substitute for this input.

For the Flutter SDK, the collector records a provenance gap if its exact Git
revision cannot be established or tracked source changes are present. A HEAD
value beside that warning does not claim the copied license bytes came from a
clean commit. A resolved Dart package without a lockfile version is also a gap.
Local source paths are not included in the manifest.

## Native probe link inputs

Evidence: `build/native-probe/CMakeFiles/thread-network.dir/link.txt` links the
following static archives into `thread-network`. The configured build cache
identifies OpenThread Commissioner source commit
`448f807e3246c46e5b82e4cdc12a9b0fb2a646ae`; its required submodules have these
exact revisions. License text paths below are relative to that source tree.

| Component | Revision / version | License evidence | Link / distribution status |
| --- | --- | --- | --- |
| OpenThread Commissioner | `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae` | `LICENSE`, BSD-3-Clause | `libcommissioner.a` and `libcommissioner-common.a` linked |
| fmt | `40626af88bd7df9a5fb80be7b25ac85b122d6c21` (11.2.0) | `third_party/fmtlib/repo/LICENSE`, MIT | `libfmt.a` linked |
| libevent | `4c908dde58ef780eeefcc9df4db3063ca62ea862` (release-2.1.11-stable) | `third_party/libevent/repo/LICENSE`, BSD-3-Clause | `libevent_core.a` and `libevent_pthreads.a` linked |
| Mbed TLS | `c765c831e5c2a0971410692f92f7a81d6ec65ec2` (v3.6.4) | `third_party/mbedtls/repo/LICENSE` says Apache-2.0 **OR** GPL-2.0-or-later | `libmbedtls.a`, `libmbedx509.a`, `libmbedcrypto.a`, `libeverest.a`, and `libp256m.a` linked |

Mbed TLS explicitly offers a choice of Apache-2.0 or GPL-2.0-or-later. The
project has not selected one; this inventory does not do so. Bundled p256-m
source carries the same dual terms. Project Everest source/header notices state
Apache-2.0 and retain separate upstream copyrights. The current collector
preserves every distinct leading copyright/license comment from Everest `.c`
and `.h` files in `commissioner/Everest-NOTICES.txt`, alongside the Mbed TLS
license containing the full Apache text. A missing Everest notice set marks
collection incomplete; absence of a separate component LICENSE file does not
justify omitting those notices.

The same Commissioner checkout has uninitialized gitlinks for COSE-C,
cn-cbor, GoogleTest, JSON and mDNS. Their exact gitlink revisions and absent
license evidence are recorded here so they are not silently mistaken for
inventoried bundled code:

| Submodule path | Gitlink revision | License file evidence | Configured link status |
| --- | --- | --- | --- |
| `third_party/COSE-C/repo` | `9401d5859e049585dd45dd1f689b6caf5bb8cd7f` | unavailable; submodule not initialized | not in link command |
| `third_party/cn-cbor/repo` | `0385f09964c5f2b1fee85189e931c607da225d37` | unavailable; submodule not initialized | not in link command |
| `third_party/googletest/repo` | `93748a946684defd1494d5585dbc912e451e83f8` | unavailable; submodule not initialized | test support, not in app link command |
| `third_party/json/repo` | `bde57124187c5732c026ffb9357c0491344c45e7` | unavailable; submodule not initialized | not in link command |
| `third_party/mdns/repo` | `a6eb0c5d5ad91f6f834a1c90798e651e0a5c3602` | unavailable; submodule not initialized | disabled with app option; not in link command |

The configured cache has `OT_COMM_APP=OFF` and `OT_COMM_CCM=OFF`; these
optional components are not shown in the native link command and are not
treated as shipped dependencies here. Recheck if build options change. The
macOS binary also links Apple CoreServices and system libraries; their platform
notices are outside this source collector.

## Dart, Flutter and engine notices

`app/pubspec.lock` pins the resolved Dart package versions. The adjacent
`.dart_tool/package_config.json` supplies local package roots. The collector
copies each uniquely named top-level license file and records missing or
ambiguous license candidates, including dev dependencies, without deciding
SPDX identifiers from filenames. `flutter_test` and `flutter_web_plugins` do
not expose package-root license files here. Their source headers identify
Flutter Authors code and refer to a BSD-style license in a `LICENSE` file; the
collector includes `packages/flutter/LICENSE` for these package roots only
when they resolve inside the configured Flutter SDK's `packages/` directory.
It records that path as provenance without assigning an SPDX identifier.
`sky_engine` does have its own top-level `LICENSE` at
`bin/cache/pkg/sky_engine/LICENSE`, which the collector copies directly; that
large notice file includes additional upstream notices and is not evidence
that other package roots inherit it.

The checked-in lockfile records Dart `3.13.7`; package config records Flutter
`3.47.8`. Flutter framework source revision is
`737ba8f885dc774b53b442759999a312c9461e4e`. The macOS arm64 Flutter SDK archive
SHA-256 recorded in `docs/THIRD-PARTY.md` is
`6114edc2dae3636cfefb7e4456a4510399ee856e324149b34dbacb509e329d05`.

The packaged macOS app contains
`Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/NOTICES.Z`
(gzip compressed). This is the artifact path used by the collector to include
the actual Flutter-generated bundle, rather than copying the Flutter SDK cache.
`app/build/web/assets/NOTICES` is another generated artifact but is not the
collector's default input. Framework and Dart SDK top-level license texts are
also collected separately from the SDK. App-specific fonts/icons and any
platform SDK artifacts should be inventoried if a later package adds them.

## Distribution gaps

- The project has no selected project license. Keep that separate from third-
  party notice collection.
- Mbed TLS's dual-license choice remains unresolved.
- The checked-in `docs/THIRD-PARTY.md` records known upstream licenses, but a
  release still needs a human-reviewed linked-library inventory, license
  selection, and complete notices for the exact target package.
- This collector is intentionally a reproducible local input collector, not a
  compliance determination. Its generated `MANIFEST.md` marks absent source
  material; review that output before using any notice bundle in a release.
