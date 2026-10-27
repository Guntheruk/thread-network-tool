# Isolated OpenThread network move lab

This lab tests one **source-network** Pending Dataset update. The source starts
with two simulated router-capable Thread devices; a third device forms a
different target network. It does not call a vendor border-router join command,
use household credentials, or establish Eero, Apple, Google, or OTBR support.
The existing application join harness remains synthetic and disabled.

## Pins and boundary

- OpenThread `v2026.10.0`: `53e8322140dde7b26827332100504507cec9cc4e`.
- Declared nested submodules: Mbed TLS `e185d7fd85499c8ce5ca2a54f5cf8fe7dbe3f8df`;
  Mbed TLS framework `457996474728cb8e968ed21953b72f74d2f536b2`.
- Toolchain base: `openthread/environment@sha256:8fc56c561f0e65ce039cbb8c665d2e5411f9c573ebe1d142417c65a47394dd26`.
- Runtime uses one container with `--network none`; its three FTD processes
  exchange simulated 802.15.4 frames over local UDP. No host networking,
  published ports, devices, household mounts, or privileged mode are used.
- The CLI sends one `MGMT_PENDING_SET` with the complete synthetic target Active
  Dataset plus one Pending Timestamp and Delay Timer. This is a network-group
  change. The target network never receives a SET. OpenThread's CLI describes
  this command as a testing interface.

The image supplies a build toolchain, avoiding host package installation.
Source fetching occurs only into the task-owned build directory. The runtime
does not have Internet access. The driver has a 600-second internal deadline
and prints a bounded, redacted JSON result for its handled failures; an outer
forced kill or host failure can prevent output. The driver never retries the SET.

## Reproduce on a Linux Docker host

Run these from the repository root. Use a fresh task-owned directory and unique
container name. The two downloads below are build inputs; they are complete
before the runtime starts.

```sh
LAB_DIR=$(mktemp -d /tmp/thread-network-tool-lab-XXXXXXXX)
cp tools/lab/Dockerfile tools/lab/protocol_lab.py "$LAB_DIR/"
git clone --depth 1 --branch v2026.10.0 \
  https://github.com/openthread/openthread.git "$LAB_DIR/openthread"
test "$(git -C "$LAB_DIR/openthread" rev-parse HEAD)" = \
  53e8322140dde7b26827332100504507cec9cc4e
git -C "$LAB_DIR/openthread" submodule update --init --recursive --depth 1
docker pull openthread/environment@sha256:8fc56c561f0e65ce039cbb8c665d2e5411f9c573ebe1d142417c65a47394dd26
docker build --network none -t tnt-protocol-lab:20261025 "$LAB_DIR"
timeout --signal=TERM --kill-after=5s 650s \
  docker run --rm --name tnt-protocol-lab-20261025 \
  --network none --read-only --tmpfs /tmp:mode=1777 \
  --user 65534:65534 --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 64 --memory 1g --cpus 2 \
  tnt-protocol-lab:20261025
```

If the outer timeout interrupts Docker before `--rm` completes, inspect the
exact named container with `docker ps -a --filter name=tnt-protocol-lab-20261025`
and remove only that task-owned container. Keep the source/image pins and JSON
report with the run record. The directory and image are task-owned build
artifacts; remove them only after checking their exact names and ownership.

## Acceptance and evidence

The driver checks that the source and target begin with distinct synthetic
Extended PAN IDs and partitions, with two source devices attached and no
pending update. After one source SET it requires a Pending Dataset on both
source devices while the target remains unchanged. It then requires both source
devices to have the target Active Dataset, no pending update, router-capable
`router` or `leader` roles, the same partition as the target, and a successful
mesh-local ping. The final target Active Dataset and pending state are checked
again. Connectivity gets at most five bounded ping attempts; the report records
the stage of a failure. A command's `Done` response alone cannot
pass the lab. An empty Pending Dataset is accepted only on the pinned CLI's
specific `Error 23: NotFound` response; any other read error fails the lab.

An initial Linux run on 25 October 2026 passed its checks, but that driver
revision did not explicitly assert final router roles. A second run asserted
source router roles and partition agreement but timed out on one ping attempt;
the cause is unproven. Both runs used the pins above, `--network none`, a
read-only filesystem and unprivileged UID. The final driver adds strict Pending
Dataset error classification, final target recheck, bounded ping retries and
an internal deadline. The frozen final driver SHA-256 was
`e27ff52aaf23b42d7fd5161251bd97fd7eafd0f2bdf44bca1f7518cda295c1d6`,
and its built image ID was
`sha256:83dc8271f12fabb9d32aa622acc99247151a85bd36e951a2cec45da5524115e2`.
Its isolated Linux run exited 0 with this allowlisted report:

```json
{"checks":{"connectivity":true,"same_partition":true,"source_converged":true,"source_distinct_before":true,"source_propagated":true,"source_router_roles":true,"target_unchanged":true},"lab":"openthread-network-pending-set","pending_set_calls":1,"schema_version":1,"stage":"complete","status":"passed"}
```

### Overall deadline review repair

Review of head `dce9d30b3e06d7ba7bdd8d2f746f365a6a51a9a2` found that the
one-shot SIGALRM raised ordinary `TimeoutError`. If it fired while waiting for
a ping response, `ping_reachable` treated it as a retryable ping timeout. An
accelerated signal reproduction returned `False` after two ping commands,
instead of stopping at the overall deadline. The fix gives SIGALRM and SIGTERM
a distinct `OverallDeadlineExceeded` exception, which propagates through ping
retries and produces `error_code: overall_deadline` in the allowlisted failure
report. Ordinary per-ping timeouts remain retryable. Two focused regression
tests check one ping maximum after the overall deadline and the typed report;
all eight protocol-lab tests pass.

The repaired driver SHA-256 is
`a26a4a9daf27fe01b93a7e1f9a3660524c424d6d1bba4f02ffaec495023a84e7`.
It was rebuilt offline against the same source and base pins above; the image
ID is `sha256:df3c9dd494036c735821c6218644bba47d26e7e0b3e94db24560094d203e16e8`.
One full isolated Linux run with `--network none`, read-only filesystem,
unprivileged UID, and no host mounts exited 0. Its report had the same all-true
checks and `pending_set_calls: 1` as the JSON above. This run validates the
normal protocol path with the repaired driver; the accelerated signal test
validates the deadline failure path.

Local Python tests cover Pending TLV construction, duplicate TLV rejection,
Pending read classification, retry behavior, and the allowlisted report:

```sh
python3 tests/tools/test_protocol_lab.py -v
```

This is actual OpenThread stack behavior under simulated radio. It does not
exercise the app's pinned Commissioner through a Border Agent, a vendor
`joinNetwork` API, accessory behavior, restart persistence, or any physical
border router. Each remains a separate compatibility gate.

References: [OpenThread simulation](https://openthread.io/codelabs/openthread-simulation),
[CLI dataset commands](https://openthread.io/reference/cli/commands),
[dataset management scope](https://openthread.io/reference/cli/concepts/dataset).
