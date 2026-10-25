# Isolated Commissioner / Border Agent read lab

Stage 1 exercises the **production `thread-network probe`** from app head
`4cc1e80e7f1df1b810b252bdef5d729f41d2dde1`. It does not use Commissioner CLI,
Petition, Pending SET, vendor APIs, household credentials, or physical radios.
This is separate from the simulated CLI Pending Dataset lab in PROTOCOL-LAB.md.
A network-wide Pending Dataset update remains unvalidated through this path.

## Inputs and build

- OpenThread: `53e8322140dde7b26827332100504507cec9cc4e` (`v2026.10.0`).
- Its Mbed TLS: `e185d7fd85499c8ce5ca2a54f5cf8fe7dbe3f8df`;
  framework: `457996474728cb8e968ed21953b72f74d2f536b2`.
- Commissioner: `448f807e3246c46e5b82e4cdc12a9b0fb2a646ae`, including its
  checked-out build dependencies: fmt `40626af88bd7df9a5fb80be7b25ac85b122d6c21`,
  libevent `4c908dde58ef780eeefcc9df4db3063ca62ea862`,
  Mbed TLS `c765c831e5c2a0971410692f92f7a81d6ec65ec2`, its framework
  `2a3e2c5ea053c14b745dbdf41f609b1edc6a72fa`.
  Other Commissioner submodules are disabled by the build options.
- Toolchain: `openthread/environment@sha256:8fc56c561f0e65ce039cbb8c665d2e5411f9c573ebe1d142417c65a47394dd26`.
- Exact app CMake/native files: `tools/lab/commissioner/app-source.sha256`.
  The image build rejects mismatched file content.

Create a fresh task-owned Linux build context with these entries:
`openthread/` and `ot-commissioner/` (complete pinned clean source trees,
including Git metadata and the initialized nested build dependencies); `app-source/`
(containing the app's `CMakeLists.txt` and `native/`); and all files from
`tools/lab/commissioner/` at the context root. Do not copy app build output,
settings, credentials or household logs. Existing pinned caches can be copied;
fetch dependencies before the offline build. When transferring from macOS,
use `COPYFILE_DISABLE=1 tar --no-xattrs` to avoid AppleDouble metadata.

The Dockerfile builds a simulated RCP and POSIX CLI. The POSIX CLI uses real
platform UDP but no platform TUN interface. `-I lo` selects the runtime's
existing loopback device. Each POSIX process forks its own simulated RCP with
a different node number and stores settings in a different tmpfs directory.
Border Agents use their real ephemeral ports, obtained through `ba port`.
Both networks form with different synthetic channels and timestamps. No mDNS
service, OTBR daemon, D-Bus, infrastructure forwarding, or Internet is required.

The app uses its existing CMake Commissioner options. Ninja and
`CMAKE_POLICY_VERSION_MINIMUM=3.5` accommodate the supplied toolchain and pinned
libevent. `audit_source.py` fails the build if the real probe's reviewed
Commissioner calls differ from Init, Connect, GetActiveDataset and
GetPendingDataset. Capability output must also report network writes false.
These checks are source/capability evidence; they are not a packet capture.

## Commands and runtime isolation

Run on a Linux Docker host, substituting only a fresh context and unique name:

```sh
docker build --network none -t tnt-commissioner-lab:20261025 /tmp/tnt-commissioner-lab-20261025
timeout --signal=TERM --kill-after=5s 210s \
  docker run --rm --name tnt-commissioner-read-20261025 \
  --network none --read-only --tmpfs /tmp:mode=1777 \
  --user 65534:65534 --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 64 --memory 1g --cpus 2 \
  tnt-commissioner-lab:20261025
```

No host network, ports, devices, volumes, capabilities or privileged mode are
added. A failed no-TUN runtime is a stop condition; do not add privileges.
The internal deadline is 180 seconds; each probe subprocess has a 35-second
wait around the production CLI's 30-second deadline. Process-group cleanup
terminates the POSIX parents; container exit removes any remaining RCP children. Docker `--rm` removes the owned runtime
container. After an outer forced kill, inspect this exact name and remove only
that task-owned container if necessary. Keep the cached image for reproduction.
An external kill or host failure may prevent a JSON report.

## Countable acceptance

1. Two distinct synthetic Border Agents form; production source and target
   probes each report authenticated, matching Active metadata including Active
   Timestamp, and empty Pending Dataset.
2. Altering only the source PSKc makes the production probe fail without claiming
   authentication. A timeout is an authentication failure, not positive proof
   of a specific DTLS alert.
3. Both full simulator Active Datasets remain unchanged after the probes;
   the source audit and executable capability permit GET operations only.
4. The runtime uses the complete isolation/deadline/resource command above;
   reports omit datasets, keys, PSKc, endpoints, labels and raw subprocess output.
5. `python3 tests/tools/test_commissioner_lab.py -v` passes six tests covering
   strict success classification, wrong-key construction, malformed/oversized
   output, bounded probe timeout, typed timeout outcome and report redaction.

The lab's JSON contains only fixed pins, enumerated stages/errors and boolean
checks. Its random synthetic credentials live only in runtime memory/tmpfs.
This stage establishes no vendor support, router restart persistence, physical
radio behavior, packaged macOS sandbox networking, or network move capability.

## Recorded evidence

On 25 October 2026, the frozen image built successfully offline and the corrected
runtime exited **0**, `stage: complete`, with all six checks true. This exercised
the exact production Probe function, including Active Timestamp, through real
Commissioner DTLS and Border Agent GET requests over loopback platform UDP.

Final image ID: `sha256:7448126f05e5f3617e58a06b9dce0b8f083efacaf7ed169cea43edc64bcc8d29`.
The run command above used this immutable ID instead of the tag and the unique
name `tnt-commissioner-read-20261025-retry`. It retained every isolation flag.
`docker inspect` after completion reported no such object: `--rm` had already
removed the container. This is cleanup evidence, not a captured running-container
configuration inspection. The invocation itself records the isolation settings.
The cached image and `/tmp/tnt-commissioner-lab-20261025` context remain on
Linuxbox. The source audit and app source manifest passed during image build.

Frozen input SHA-256 values:

- Driver: `8537fa3a23f2e460c06def10aecdb2c9201d8451a362da938f21bbb1732f42cb`.
- Dockerfile: `8a2b4fccbcaaac7e34db3684ef28e38a1b5c63dcbf5aef341b8284fa10cf7104`.
- App source manifest: `be0efc371087ae1770ccdf40d9e0d2f51e8c9a4fd5f9d00d7d1e6fd1b4c8919e`.

The allowlisted final runtime report was:

```json
{"checks":{"datasets_unchanged":true,"distinct_networks":true,"read_only_capability":true,"source_authenticated":true,"target_authenticated":true,"wrong_pskc_rejected":true},"lab":"commissioner-border-agent-read","pins":{"app":"4cc1e80e7f1df1b810b252bdef5d729f41d2dde1","commissioner":"448f807e3246c46e5b82e4cdc12a9b0fb2a646ae","openthread":"53e8322140dde7b26827332100504507cec9cc4e"},"schema_version":1,"stage":"complete","status":"passed"}
```

The first runtime image, `sha256:af5d1351dfe848afd2220edb16bd81a1796560586a1469fb6b5d4c80cc6c91e9`,
failed closed at `form-networks` with `simulator_command`, before a DTLS probe.
Its driver used `ba start`; exact-pin `src/cli/cli_ba.cpp` supports `ba enable`.
Correcting that setup verb resolved the failure. The corrected driver also adds
an allowlisted command label and bounded integer CLI error code on command
rejection, without arguments or raw output. No runtime privileges changed.

All six local driver tests passed after the correction, including checks that
unknown command labels/error details cannot leak secrets. Stage 1 establishes
a real read-only Commissioner/Border Agent path in this simulator arrangement.
A Petition/Pending SET adapter, source authorization, propagation, convergence,
one-shot dispatch and observation/recovery remain separate Stage 2 work.
