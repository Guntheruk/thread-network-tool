# Third-party provenance

Initial protocol baseline: OpenThread Commissioner commit `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae`, BSD-3-Clause, https://github.com/openthread/ot-commissioner . Optional Commissioner builds use the generated modified source profile in `patches/commissioner/manifest.json`: typed legacy Wakeup Channel TLV 74 support and a bounded read-only raw Pending GET. Pending writes still use the public typed setter; there is no raw setter. The patch retains upstream copyright and BSD-3-Clause terms. `tools/prepare_commissioner_source.py` verifies clean parent/recursive pins, patch hash and generated-tree provenance without modifying dependency caches. CMake verifies provenance at configure and before Commissioner builds. Retain `tnt-source-provenance.json`, the manifest and patch with notice-generation inputs; rebuild all consumers against the modified public dataset struct. Default CMake builds do not link Commissioner or install a move worker; the Mac packaging script explicitly opts into the read-only Commissioner probe. The optional POSIX journal helper has no network access.

Build workarounds for the pinned source: disable unused commercial commissioning support and CLI/tests; remove the Debug fmt archive suffix expected incorrectly by the upstream CMake; demote a newer AppleClang uninitialized-const-pointer warning in upstream mbedx509. These are build compatibility measures, not a dependency security review.

Relevant transitive libraries: libevent (BSD-3-Clause), fmt (MIT), and Mbed TLS (the inspected pinned source offers Apache-2.0 OR GPL-2.0-or-later). A final linked-library inventory, version review, license selection, and notices are required before distributing binaries.

UI/toolchain used for this initial build: Flutter 3.47.8, framework revision `737ba8f885dc774b53b442759999a312c9461e4e`, Dart 3.13.7. The macOS arm64 SDK archive SHA-256 was verified against the official release manifest: `6114edc2dae3636cfefb7e4456a4510399ee856e324149b34dbacb509e329d05`. Flutter framework is BSD-3-Clause; engine/bundled dependencies have their own notices. App Dart dependencies are pinned in app/pubspec.lock; ffi 2.2.0 is BSD-3-Clause.

Apple ThreadNetwork credential bridges and the Android Google Play services
Thread Network SDK credential bridge are implemented. Their unsigned iOS and
historical Android debug builds do not establish real consent/retrieval or
native Mac provisioning. Google Home device APIs/account integration remain
planned and absent. These platform SDK access and distribution terms are
distinct from open-source sample licenses; inventory the artifacts actually
included in each target package.


Current collection uses only a verified generated Commissioner tree. Run
`tools/collect_third_party_notices.py --commissioner-root /absolute/generated/source`
with the matching Flutter SDK, resolved app packages and packaged Flutter notices.
The collector verifies the complete tree before and after collection, takes
original revisions from its verified provenance instead of expecting `.git`,
and copies the source provenance, original-pin manifest and exact modification
patch beside the verbatim license inputs. Missing Flutter/package/artifact
inputs still produce an incomplete notice inventory; provenance is not guessed.

Mbed TLS's bundled p256-m source carries its dual Apache-2.0 OR
GPL-2.0-or-later terms. Bundled Project Everest source/header notices separately
state Apache-2.0 and retain INRIA/Microsoft and other upstream copyrights. The
collector preserves every distinct leading Everest copyright/license block in
`commissioner/Everest-NOTICES.txt` alongside the Mbed TLS license containing the
full Apache text. The inventory does not choose between the Mbed TLS alternatives
or approve a distribution license.

## Lab-only OpenThread correction

The isolated router simulation additionally uses OpenThread
`53e8322140dde7b26827332100504507cec9cc4e`. Its reviewed own-MAC-counter patch,
original/patched source hashes and regression are retained in
`tools/lab/openthread-counter-fix/`; see `SIMULATOR-COUNTER-FIX.md` for scope.
This is a local patch, not an upstream acceptance claim. The simulated router
stack is not bundled with the Mac app; its Commissioner library and collected
binary notices are unchanged by this lab repair.

## Developer alpha licence decision

The owner selected Apache-2.0 for original project code on 27 October 2026.
The Mac developer prerelease uses the Apache-2.0 option for dual-licensed Mbed
TLS/p256-m, preserving original licence texts and separate Everest notices.
See [Licensing](LICENSING.md) and the exact release asset receipt. This decision
does not relicense upstream code or establish platform SDK access permissions.
