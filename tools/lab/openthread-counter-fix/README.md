# Pinned OpenThread lab correction

These are Linux, offline, synthetic lab recipes. They do not run the Mac app or
contact household devices. See [the diagnosis and evidence](../../../docs/SIMULATOR-COUNTER-FIX.md).
The patch changes only the lab's OpenThread host stack; the application's
Commissioner library and packaged Mac binaries are unchanged.

Prerequisite: the existing frozen full-app lab image is cached locally. It is
not published, and these files do not provide a clean-clone bootstrap for it.
The original lab construction is documented in
[application integration](../../../docs/NETWORK-MOVE-APP-INTEGRATION.md).
Builds make no dependency downloads. Do not silently substitute a newer tag.

## Native red/green regression

From this directory, on the Linux lab host with Docker and GNU `timeout`:

```sh
set -eu
expected_base=sha256:5a8f1acb35081de5188db0eebebd8e3c2b315dd9b42cf19f9c7a664401e356e9
test "$(docker image inspect --format '{{.Id}}' tnt-full-app:787ace4)" = "$expected_base"
docker build --network none --pull=false -t tnt-framecounter-unit:recipe-review .
test "$(docker image inspect --format '{{.Id}}' tnt-full-app:787ace4)" = "$expected_base"
container_id=$(docker create --user 0:0 --network none --read-only \
  --cap-drop ALL --security-opt no-new-privileges --cpus 2 --memory 4g \
  --pids-limit 512 --tmpfs /work:rw,exec,size=3g \
  --tmpfs /tmp:rw,exec,size=256m --tmpfs /evidence:rw,exec,size=64m \
  tnt-framecounter-unit:recipe-review)
trap 'docker rm -f "$container_id" >/dev/null 2>&1 || true' EXIT
timeout --kill-after=5s 240s docker start -a "$container_id"
test "$(docker inspect --format '{{.State.ExitCode}}' "$container_id")" = 0
```

`run.sh` verifies the original source hash, compiles the real native test,
requires the exact original counter mismatch/exit 255, applies the normalized
hash-checked patch, and requires the repaired test to pass. The same-key case
must preserve its existing nonzero counter. `GetMaximumMacFrameCounter()` must
match the single IEEE 802.15.4 counter. The container has no host bind, devices
or external network; UID 0 is confined to its read-only/capability-dropped
namespace and writable tmpfs. The full application fixture runs separately as
UID 65534, not through this unit-test recipe.

## Corrected full-fixture image

`Dockerfile.patched` rebuilds only `ot-cli` in the cached POSIX configuration.
`build-patched.sh` validates source and patch hashes, then checks the RCP,
configuration and original application/fixture files remain byte-identical.
Use a new result tag and retain the original image for the failing comparison:

```sh
set -eu
expected_base=sha256:5a8f1acb35081de5188db0eebebd8e3c2b315dd9b42cf19f9c7a664401e356e9
test "$(docker image inspect --format '{{.Id}}' tnt-full-app:787ace4)" = "$expected_base"
docker build --network none --pull=false -f Dockerfile.patched \
  -t tnt-full-app:counter-fix-reproduction .
test "$(docker image inspect --format '{{.Id}}' tnt-full-app:787ace4)" = "$expected_base"
docker image inspect --format '{{.Id}}' tnt-full-app:counter-fix-reproduction
```

This builds an image; it does not start a migration. Before a full run, record
its immutable image ID and use the isolation, outer deadline and exact scenario
in the linked integration document. Keep all seven independent oracle gates,
the five-minute activation interval and the original processes across recovery.
Do not weaken connectivity checks, replay a SET, or substitute real routers.
`hash-full-fixture.sh` is the additional read-only census used for the recorded
base-versus-patched comparison. Its output contains software paths and hashes,
not network credentials.

The captured full-run image predates the expanded build-time census in this
recipe: its same 3,132 files were independently compared after the build. The
one-line patch, native regression and resulting OpenThread source are identical.
A rebuilt image ID is expected to differ; the recorded evidence does not claim
that a later build has already run the full application fixture.
