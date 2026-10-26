# Local Mac alpha acceptance — 26 October 2026

Production source: `7422ddc8a3b14dec75acb2a005c59198b39d3bc9`, branch
`feat/mac-eero-alpha`. Built from a clean checkout using normal `lib/main.dart`,
`TNT_MAC_ALPHA=1`, full Xcode and verified pinned Commissioner source. No
test entrypoint, home credential, household discovery or household operation was
used for the production-window check.

## Local artifacts

- `build/mac-alpha-7422ddc/Thread Network Tool.app`
- `build/mac-alpha-7422ddc/local-acceptance.json`: exact binary hashes,
  architecture, signature and observed window results.
- `build/mac-alpha-7422ddc/release-notices/`: 44 collected notice inputs and
  provenance; no project licence choice is implied.
- `build/Thread-Network-Tool-Mac-alpha-7422ddc.zip`: local app, acceptance,
  dependency provenance and notices. No publication or hosted job was performed.

The application and all three helpers contain arm64 and x86_64 slices. Strict
recursive signature verification passed. Signing is local ad hoc; this is not
a notarized or Developer ID signed release. No valid signing identity was
installed on the build Mac. Runtime inspection was on Apple Silicon only.

## Observed production window

The actual new executable opened with “Live · Eero join available after review”
and “Join Eeros to a network”. Discovery remained idle. The join page showed
the network being kept, Eeros being moved, whole-source scope, and empty-network
and inventory confirmations. No router was discovered, read or changed.

Credential setup offered guided eero copying, existing Home Assistant and
Advanced entry. It stated that this Mac app cannot retrieve Apple credentials.
The complete synthetic `AlphaTest` dataset imported through the bundled native
parser into the source role. After quitting, confirming process exit and
reopening, both credential roles were empty again. No household credentials
were used or retained.

## Execution evidence

- Final Flutter analysis: no issues. Full suite: 178 passed, one Linux-only
  isolated runtime test skipped. The real journal was supplied explicitly so
  both Mac session integration tests ran.
- Automatic checking and no-replay behavior were independently reviewed at
  `4437c011c25f978dc132e64cfe89f3fcd745470c`: no P1/P2 finding. The final changes
  after that head only clarify copy, hide unavailable Mac Apple retrieval,
  document scope and test that route; its focused dialog suite passed 10 tests.
- Native worker review at `fb68f74960b129141b8d6f17deebb9376f91060d`: no P1/P2
  finding. Six scoped native CTests, including protocol and real wire tests,
  passed. The separate native dropped-response case proved uncertain outcome
  and refused replay after terminating the worker once the fixture received SET.
- A signed Flutter test parent ran the actual bundled worker and journal with
  inherited sandbox entitlements. Five loopback scenarios passed: accepted,
  rejected, mismatched fence, changed target and silent target. Accepted and
  rejected cases each invoked one source Pending SET, with zero target SETs;
  the other three cases invoked zero SETs.
- The production move worker SHA-256 is
  `de042a90660a210c88e6a70b9e6e109b6e19cf0cfb59aa5c5f82001f29103520`;
  the journal SHA-256 is
  `1842c21a13fdc25b7428d877c0f8ddc6a215e287cc7f5ba7c6a619ad8c18c1e6`.
  Both are byte-identical to the signed-parent wire test package.
- Signed-parent evidence is retained at
  `build/mac-alpha-sandbox-fb68f74/macos-move-sandbox-evidence.json`. Its later
  configuration state was modeled by replacing synthetic peers; it did not
  demonstrate a retail router transition or wait through an actual five-minute
  mesh transition. Delay, stable interval and restart gates have separate
  controller/session/widget test evidence.

The older Linux key-change scenario still failed its independent connectivity
check. This remains recorded in `PROGRESS.md`; Mac configuration verification
does not weaken or satisfy that separate mesh-connectivity check.

## Still required before broader distribution

Controlled Eero model/firmware acceptance, clean-Mac installation, trusted
signing/notarization, Intel execution, and the owner's licence/distribution
decision remain open. Automatic Apple credential retrieval, phone companions,
Google Home commands, Windows networking and accessory migration are outside
this bounded alpha. The owner's working household has not been used as a test
network. All source commits and package artifacts remain local under the push
and cloud-cost hold.
