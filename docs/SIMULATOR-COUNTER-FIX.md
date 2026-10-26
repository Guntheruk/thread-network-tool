# Pinned OpenThread simulator counter fix

This repair belongs to the isolated OpenThread router stack. It changes neither
Thread Network Tool's Mac binaries nor Eero firmware. It is unrelated evidence
to the household IKEA sensor investigation.

## Reproduced fault

The frozen application is `787ace4d43d2317744238d172d94e0b892b89677`, running
OpenThread `53e8322140dde7b26827332100504507cec9cc4e`. Its key-change/older-target
scenario reached matching datasets, no pending changes, a common partition,
source router roles and an unchanged target, but failed independent IP traffic.

A new unpatched run retained the failure for 548 seconds. Current addresses
matched the target mesh-local prefix, RLOCs were unique, and all key sequences
were zero. Cross-network pings failed in both directions using both ML-EIDs and
RLOC addresses; the original source peers still communicated. This excludes a
simple stale-address or key-sequence mismatch in this reproduction.

The pinned `KeyManager::SetNetworkKey()` resets received neighbor counters but
leaves its own transmitted counter unchanged. The simulation radio resets its
transmitted counter when it installs the new MAC key. In the tested single-radio
configuration, MLE advertises the host's higher counter, so subsequent lower
radio counters can fail the peer's replay protection. The existing
`SetCurrentKeySequence()` already resets own counters before key installation;
the patch applies that same ordering to a genuinely changed Network Key.

Source anchors at the exact upstream revision:

- [Key replacement, counters and existing ordering](https://github.com/openthread/openthread/blob/53e8322140dde7b26827332100504507cec9cc4e/src/core/thread/key_manager.cpp)
- [Simulation radio key installation](https://github.com/openthread/openthread/blob/53e8322140dde7b26827332100504507cec9cc4e/examples/platforms/simulation/radio.c)
- [MLE Link Frame Counter](https://github.com/openthread/openthread/blob/53e8322140dde7b26827332100504507cec9cc4e/src/core/thread/mle.cpp)
- [MAC replay validation](https://github.com/openthread/openthread/blob/53e8322140dde7b26827332100504507cec9cc4e/src/core/mac/mac.cpp)

## Direct regression and repair

The [native regression](../tools/lab/openthread-counter-fix/test_network_key_counter.cpp)
links the actual pinned KeyManager and SubMac with test-platform radio hooks
modeling the simulation radio's key-install reset. It does not disable replay
protection or substitute a parser-only test.

| Check | Unpatched | Patched |
| --- | --- | --- |
| Host/SubMac counter after new key | 12,345 | 0 |
| Radio counter after new key | 0 | 0 |
| Own counters reset before key installation | No | Yes |
| Expected regression exit | 255 | 0 |
| Identical-key call preserves nonzero counter 6,789 and skips reinstall | Not reached | Pass |

The [one-line patch](../tools/lab/openthread-counter-fix/reset-own-counter.patch)
resets own counters before installing the replacement key. Its SHA-256 is
`10d162fa0969abc268a4930d146f6ccbaf4de03d0746f7aaf2aeb3778740b4ff`.
Original `key_manager.cpp` SHA-256:
`58947b0c77d3aaa91b3b12b47dce5f02c1afcfabd9db3736e8342b92409b53fe`;
patched: `df1c551a7d9a03637f1a7fc6db9b3894763987a39b5e6b91bd9caa7ca5873360`.
Independent review found no actionable finding in this scoped correction.

The test records key references disabled, single radio and TREL disabled.
It checks that the advertised maximum getter equals the IEEE 802.15.4 counter;
it does not serialize an MLE packet. Multi-radio, software-security radios and
KeyRef-storage configurations remain untested. The separate `SetNetworkKeyRef()`
API is not patched; its reference-versus-key-material equality needs separate
analysis before extending this fix.

## Full application comparison

The unchanged full application fixture passed in 375.3 seconds with 133 fresh
samples. It reached `verified_complete` after two real Flutter test processes:
one explicit Petition/SET, stopped observation, then restored recovery without
redispatch. All seven original oracle gates passed, including independent IP
connectivity. All seven directional ping controls passed at first convergence
and immediately before disposal; every router had two reciprocal neighbor links.
The container exited zero and was removed. No timing or success gate was relaxed.

| Original gate | Unpatched | Patched |
| --- | --- | --- |
| Complete source dataset matches target | Pass | Pass |
| Target unchanged | Pass | Pass |
| Source has no pending dataset | Pass | Pass |
| Target has no pending dataset | Pass | Pass |
| Same partition | Pass | Pass |
| Source processes remain router roles | Pass | Pass |
| Independent connectivity | Fail | Pass |

The normalized-patch native recipe also passed a separate run with exact
source/patch hashes and the specific expected original failure enforced.
The [bounded evidence receipt](../tools/lab/openthread-counter-fix/evidence.json)
retains pins, results, isolation and artifact hashes. Full diagnostic evidence
SHA-256: `b56abceb32d64df00e45d7f3831a854ff42a918914e2078421db910643b0628c`;
unpatched comparison: `4738b4d603b64134d387ea6726f62466c1a58477e9465f8e538a3e5908a5a544`.

The corrected image is
`sha256:4340ad605da9d31c84243a85b4e6807267720c673a0de240639a35708dcf632e`.
It derives from frozen image
`sha256:5a8f1acb35081de5188db0eebebd8e3c2b315dd9b42cf19f9c7a664401e356e9`.
Only the OpenThread host CLI was rebuilt; simulation RCP, POSIX build settings
and all 3,132 application/fixture/runner/cache files were unchanged. Both file
manifests hash to `f02d886051cb48a4d19403e7f5b3d045e95dc50bf700269f9c0327d197c9a775`.

| Component | SHA-256 |
| --- | --- |
| Original host CLI | `15707be024283fba81bdb3630576658b9cb5e9bbb463faadc33e1993602ed0c3` |
| Patched host CLI | `37c96ebc62c90dbe9194f0f16d80ad0c6ec56332f82cdd66203ea9ea65c7b6dc` |
| Unchanged simulation RCP | `661bd3ffc7c2eb38f428dbfbb777456b846ae2078d320a1ed103eefab455af5b` |
| Unchanged POSIX CMake cache | `30ccb4c54606415ca70a047c4943fb2d4c949130e0f2441d34988c142184c1ef` |

The application, worker, independent oracle, five-minute activation delay and
read-only diagnostic instrumentation were preserved. No household network is
used. This software-fixture pass establishes the repair in this pinned
reproduction only; packaged Mac/retail Eero migration and recovery still require
their own test. The production Mac app remains at `7422ddc`; the lab radio stack
is not bundled with it, and its completion claim stays `verified_configuration`.

## Reproduction materials

[Lab recipes](../tools/lab/openthread-counter-fix/README.md) retain the patch,
real native regression, guarded offline image preparation and source hashes.
They require the existing frozen Linux lab image; they are not a fresh-clone
bootstrap or an instruction to test on household routers. Historical baseline
images are left intact so the failure remains reproducible.

The bounded evidence is local under `/tmp/tnt-ot-framecounter-fix`,
`/tmp/tnt-keychange-state-diagnostic-20261026`, and
`/tmp/tnt-keychange-framecounter-patched-20261026` on the lab host and Mac.
These directories contain synthetic diagnostics only; they are not uploaded.
