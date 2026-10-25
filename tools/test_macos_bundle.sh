#!/usr/bin/env bash
set -euo pipefail

die() { printf 'test_macos_bundle: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || die 'macOS is required'
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmake_bin="${TNT_CMAKE_BIN:-cmake}"
command -v "$cmake_bin" >/dev/null 2>&1 || die "CMake unavailable: $cmake_bin"
mkdir -p "$project_root/build/packaging-tests"
test_root="$(mktemp -d "$project_root/build/packaging-tests/relocation.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
native_build="$test_root/native-build"
first_app="$test_root/staged/Synthetic.app"
moved_app="$test_root/moved/Synthetic.app"
signed_app="$test_root/signed/Synthetic.app"
mkdir -p "$first_app/Contents" "$test_root/moved"
mkdir -p "$first_app/Contents/MacOS"
cat > "$test_root/parent.c" <<'C'
#include <mach-o/dyld.h>
#include <spawn.h>
#include <sys/wait.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

extern char **environ;
int main(void) {
    fputs("signed parent entered\n", stderr);
    char executable[PATH_MAX];
    uint32_t size = sizeof executable;
    if (_NSGetExecutablePath(executable, &size) != 0) return 91;
    char *slash = strrchr(executable, '/');
    if (slash == NULL) return 91;
    *slash = '\0';
    char helper[PATH_MAX];
    if (snprintf(helper, sizeof helper, "%s/../Helpers/thread-network", executable)
        >= (int)sizeof helper) return 91;
    char *const arguments[] = {helper, "inspect", NULL};
    pid_t child = 0;
    if (posix_spawn(&child, helper, NULL, NULL, arguments, environ) != 0) {
        fputs("signed parent could not launch helper\n", stderr);
        return 92;
    }
    fputs("signed parent spawned helper\n", stderr);
    int status = 0;
    if (waitpid(child, &status, 0) != child) return 93;
    if (WIFEXITED(status)) {
        fprintf(stderr, "signed helper exited %d\n", WEXITSTATUS(status));
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        fprintf(stderr, "signed helper signal %d\n", WTERMSIG(status));
    }
    return 94;
}
C
cc "$test_root/parent.c" -o "$first_app/Contents/MacOS/Synthetic"
python3 - "$first_app/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({'CFBundleExecutable': 'Synthetic',
                   'CFBundleIdentifier': 'example.local.synthetic',
                   'CFBundlePackageType': 'APPL',
                   'CFBundleVersion': '1'}, output)
PY
mkdir -p "$test_root/signed"
/usr/bin/ditto "$first_app" "$signed_app"
"$cmake_bin" -S "$project_root" -B "$native_build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
  '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' \
  -DTNT_WITH_COMMISSIONER=OFF -DTNT_BUILD_TESTS=OFF
"$cmake_bin" --build "$native_build" --parallel 4
TNT_CMAKE_BIN="$cmake_bin" "$project_root/tools/bundle_macos_helper.sh" \
  "$native_build" "$first_app" none
TNT_CMAKE_BIN="$cmake_bin" "$project_root/tools/bundle_macos_helper.sh" \
  "$native_build" "$signed_app" local
codesign --verify --strict "$signed_app/Contents/Helpers/thread-network"
codesign --verify --deep --strict "$signed_app"
codesign -d --entitlements :- "$signed_app" 2>/dev/null | \
  python3 -c 'import plistlib,sys; d=plistlib.loads(sys.stdin.buffer.read()); assert d["com.apple.security.app-sandbox"] is True'
mv "$first_app" "$moved_app"
rm -rf "$native_build"

fixture="$(python3 - <<'PY'
items=[(0,bytes([0,0,15])),(1,bytes([0x12,0x34])),(2,bytes(range(1,9))),
       (3,b'Synthetic'),(4,bytes([0xaa])*16),(5,bytes([0xbb])*16),
       (7,bytes([0xfd])*8),(12,bytes([0,0,0])),
       (14,bytes([0,0,0,0,0,0,0,1])),(53,bytes([0,4,0,1,0,0]))]
print(b''.join(bytes([kind,len(value)])+value for kind,value in items).hex())
PY
)"
helper="$moved_app/Contents/Helpers/thread-network"
result="$(cd / && printf '%s\n' "$fixture" | "$helper" inspect)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["valid"] is True; assert d["network_name"] == "Synthetic"; assert d["channel"] == 15; assert "network_key" not in d and "pskc" not in d' "$result"
set +e
invalid="$(cd / && printf 'ff\n' | "$helper" inspect)"
invalid_status=$?
set -e
[[ "$invalid_status" != 0 ]] || die 'malformed dataset unexpectedly succeeded'
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["valid"] is False; assert "ff" not in d.get("message", "")' "$invalid"
[[ "$result" != *"$fixture"* && "$invalid" != *"$fixture"* ]] || die 'result exposed input dataset'
printf 'Relocation smoke passed: installed helper ran after moving app and deleting its native build tree.\n'

parent="$signed_app/Contents/MacOS/Synthetic"
signed_result="$(cd / && printf '%s\n' "$fixture" | "$parent")"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["valid"] is True; assert d["network_name"] == "Synthetic"; assert d["channel"] == 15; assert "network_key" not in d and "pskc" not in d' "$signed_result"
set +e
signed_invalid="$(cd / && printf 'ff\n' | "$parent")"
signed_invalid_status=$?
set -e
[[ "$signed_invalid_status" != 0 ]] || die 'signed parent accepted malformed dataset'
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["valid"] is False; assert "ff" not in d.get("message", "")' "$signed_invalid"
[[ "$signed_result" != *"$fixture"* && "$signed_invalid" != *"$fixture"* ]] || die 'signed path exposed input dataset'
printf 'Sandbox inheritance smoke passed: signed parent launched signed helper for valid and invalid synthetic inspections.\n'
