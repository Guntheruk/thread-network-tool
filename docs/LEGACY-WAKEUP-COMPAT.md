# Legacy Wake-up Channel compatibility

The optional native adapter preserves legacy dataset TLV 74 through the existing
typed `SetPendingDataset` API. Its generated-source build and full-wire adapter
checks are integrated. This adds no consumer application command, raw setter or
household operation. Native runtime and vendor support remain separate gates.

Do not describe this as finalized Thread 1.4 or Thread Direct compliance.
[OpenThread PR 13614](https://github.com/openthread/openthread/pull/13614)
removed the legacy experimental Wake-up Channel from Operational Dataset APIs
on 22 September 2026. Its inclusion in older vendor-shaped datasets remains a
compatibility concern, without establishing any vendor's current behavior.

The Commissioner public main SHA checked on 25 October 2026 was already the
pinned `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae`; no newer public pin was
available to solve the missing typed field. The historical OpenThread source at
`c71f802c39611af67d78a957d27199a81d989b24` defines type 74 as the ordinary
Channel value: one page byte followed by a big-endian uint16 channel. Its
[validation](https://github.com/openthread/openthread/blob/c71f802c39611af67d78a957d27199a81d989b24/src/core/thread/mle_tlvs.cpp#L279)
requires a supported page and an in-range radio channel; it does not use the
CSL subclass's zero-channel sentinel. This application's deliberately narrower
profile permits only page 0 and channels 11–26.

## Typed extension and boundaries

`ActiveOperationalDataset` gains `Channel mLegacyWakeupChannel` and
`kLegacyWakeupChannelBit = (1 << 3)`. `PendingOperationalDataset` inherits both;
its existing bits 5 and 4 are unchanged. Storage initializes to zero while
presence stays clear. The field is included only when its flag is set.

The patch recognizes the legacy type in Active/Pending dataset membership,
GET selection, typed decode and typed encode. Active SET explicitly rejects it;
Pending SET retains the existing mandatory timestamps, delay, active-state and
session checks. No setter or private interface is added. Both the application
and every linked native object must be rebuilt against the changed struct.

The upstream generic parser drops invalid/unknown TLVs and overwrites duplicate
types. A narrow raw prevalidation pass makes malformed or duplicate TLV 74 an
error before the typed dataset decoder calls that parser. Encoding checks the
legacy value before appending any dataset bytes.

The application adapter still owns stricter whole-dataset validation: reject all
unsupported types, all duplicate types, malformed lengths, invalid values, and
incomplete/oversized datasets before projecting into the typed structure.
Compare the full supported type/value multiset before and after projection.
Unknown types must never be silently discarded because the library offers a
typed setter. The native tests explicitly check that an unknown type is outside
the Operational Dataset membership set; they do not claim the generic upstream
GET parser rejects every unknown type. The root-owned adapter tests must prove
that rejection happens before dispatch. This dependency patch alone cannot
establish the application's complete write path or vendor compatibility.

## Reproduce without changing dependency caches

Use Python 3.12+ and a clean local checkout at the exact pin, with fmtlib,
libevent, Mbed TLS and Mbed TLS's recursive framework submodule initialized at
the revisions in `patches/commissioner/manifest.json`:

```sh
python3 tools/prepare_commissioner_source.py \
  --source /absolute/path/to/clean/ot-commissioner \
  --output /absolute/path/to/fresh/generated-source
python3 tools/prepare_commissioner_source.py \
  --verify-only --output /absolute/path/to/fresh/generated-source
```

Preparation checks the parent and recursive Git pins, dirty/untracked source,
and patch hash. It archives only tracked files at the explicit revisions,
applies the reviewed patch into a new source copy, checks the result against the
independent `prepared_tree_sha256` committed in the manifest, and writes
`tnt-source-provenance.json`. The current digest was independently reproduced
from the clean pinned Git sources; it is not learned from a supplied generated
tree. Verification requires both exact manifest provenance and this committed
tree identity. Replacing source and recomputing the adjacent provenance hash
cannot authorize a different tree. It performs no fetch, checkout or source-cache
mutation. It refuses an existing output or a nested input/output relationship.
The generated source has no `.git`; build integration must use provenance
verification instead of asking it for a Git HEAD. Verify again before each
configure/build and retain the source/provenance alongside build evidence.

The manifest records the source SHA, recursive revisions, patch SHA-256,
compatibility profile, required build options and expected prepared-tree hash.
The hash covers all copied files, their canonical modes and symlink targets,
excluding only the provenance file itself. Preparation maps Git's executable
files to mode 0755 and other regular files to 0644, independently of host umask;
directory permissions are not part of identity. Preparation twice must produce
identical identity. Transport generated trees without adding metadata files:
Mac BSD tar can include AppleDouble `._*` entries that Linux Docker extraction
materializes. Python `tarfile` transport was verified to retain the same tree
and modes across Mac/Linux; extra files must continue to fail verification.
Set `PYTHONDONTWRITEBYTECODE=1` for configure/build, as the focused CMake test
project does; otherwise Mbed TLS's script imports add Python cache files to the
generated tree and verification correctly rejects the changed tree. Keep build
outputs outside generated sources. Do not relax tree verification to hide new
files.

The root CMake and adapter now require and verify the generated source.
Disable the unused upstream app, tests, Java bindings and commercial
commissioning as specified by the manifest; enabling other features requires a
fresh dependency inventory. Existing AppleClang/fmt build compatibility options
remain necessary and are shown in the standalone test CMake project.

## Synthetic verification

```sh
TNT_COMMISSIONER_TEST_SOURCE=/absolute/path/to/clean/ot-commissioner \
  python3 -m unittest discover -s tests/tools \
  -p test_prepare_commissioner_source.py -v
cmake -S patches/commissioner/tests -B /absolute/path/to/fresh/test-build \
  -DTNT_COMMISSIONER_SOURCE=/absolute/path/to/fresh/generated-source \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /absolute/path/to/fresh/test-build --parallel
ctest --test-dir /absolute/path/to/fresh/test-build --output-on-failure
```

The C++ executable uses the existing upstream friend `CommissionerTestPeer`
only in the test translation unit. It exercises the actual patched Active and
Pending decoder and Pending encoder, without exporting a raw production API.
Three full-field fixtures cover absent TLV 74 and both channel boundaries;
semantic equality compares every encoded type/value. Negative fixtures cover
short/truncated/oversized values, unsupported page, zero/out-of-range channels,
duplicate 74 and invalid typed inputs. GET type selection and membership are
checked separately. No test opens a network session or sends a packet.

Source preparation tests cover patch tampering, dirty/wrong parent pins,
uninitialized repositories, recursive submodule mismatch/dirty state, refusing
overwrite, directory alias containment, hash changes, actual clean-source
reproducibility, canonical modes across umasks, resolver reuse, a fabricated tree
with rewritten provenance and generated-source tampering followed by a rehash. The actual-source integration is
explicitly skipped unless `TNT_COMMISSIONER_TEST_SOURCE` is supplied; skipped
integration is not reproducibility evidence.

Historical evidence from the original patch: the unmodified public header rejects both new
member names at compile time. The prepared source builds in Release, and the
actual codec executable passes 283 checks covering three complete round trips
and 17 negative fixtures. The focused CTest passes 1/1. All 11 preparation tests
pass with the real pinned source integration enabled. The generated source
passes its full tree verification again after configure/build; its tree hash is
`41975e0bf6c3aaa68a50075c9c00b82007b3f357a879e2b6cde4f71cbb97b1d5`.
These checks do not dispatch `SetPendingDataset`, establish eventual adoption,
or test Apple/Eero hardware.

The subsequent integrated patch also exposes bounded raw Pending GET. Strict
adapter parsing rejects unknown, duplicate and malformed full-wire fields before
they can be mistaken for empty/exact pending data. The integrated build passes
seven CTests, including 284 codec checks and 73 adapter checks with three complete
projections. Its generated tree hash is
`69f848c0395b356c7594aec2fd27539d03bce062d3dfb007c617d3266aaa66f7`;
the patch identity is recorded in the current manifest. This is build/codec
evidence, not a new network-runtime result.

## Notices and provenance

The patch retains upstream copyright headers and BSD-3-Clause terms. Source
archives preserve upstream and transitive licence files. The generated
provenance identifies the modification instead of describing it as unmodified
upstream. Binary notices must reproduce the upstream copyright, conditions and
disclaimer, plus the required transitive notices. Update `docs/THIRD-PARTY.md`'s
description of the modified dependency with its generated source provenance in
notice collection.
This work does not select an application licence, select among dependency
licence alternatives, approve distribution, or claim a security review.
