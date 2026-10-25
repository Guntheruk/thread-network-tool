#!/usr/bin/env bash
set -euo pipefail

die() { printf 'bundle_macos_helper: %s\n' "$*" >&2; exit 1; }
[[ $# == 3 ]] || die "usage: $0 NATIVE_BUILD_DIR APP_PATH none|local|developer-id"
native_build="$1"
app="$2"
mode="$3"
[[ "$(uname -s)" == Darwin ]] || die 'macOS is required'
[[ -d "$native_build" && -d "$app/Contents" ]] || die 'native build and .app/Contents must exist'
[[ "$mode" == none || "$mode" == local || "$mode" == developer-id ]] || die 'invalid signing mode'
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmake_bin="${TNT_CMAKE_BIN:-cmake}"
command -v "$cmake_bin" >/dev/null 2>&1 || die "CMake unavailable: $cmake_bin"
rm -f "$app/Contents/Helpers/thread-network" "$app/Contents/Frameworks/libthread_network_core.dylib"
"$cmake_bin" --install "$native_build" --prefix "$app/Contents"
helper="$app/Contents/Helpers/thread-network"
core="$app/Contents/Frameworks/libthread_network_core.dylib"
[[ -x "$helper" && -f "$core" ]] || die 'CMake install omitted the native helper or core'

# The installed Mach-O files must remain valid after the build directory moves.
# Universal binaries print a filename heading for each architecture. Keep only
# dependency rows so those headings cannot look like build-path dependencies.
helper_loads="$(otool -L "$helper" | awk '/^[[:space:]]/ {print}')"
core_loads="$(otool -L "$core" | awk '/^[[:space:]]/ {print}')"
helper_rpaths="$(otool -l "$helper" | awk '/cmd LC_RPATH/{found=1;next} found && /path /{print $2;found=0}')"
core_id="$(otool -D "$core" | sed -n '2p')"
[[ "$core_id" == '@rpath/libthread_network_core.dylib' ]] || die "unexpected core install ID: $core_id"
[[ "$helper_loads" == *'@rpath/libthread_network_core.dylib'* ]] || die 'helper does not load bundled core by @rpath'
[[ "$helper_rpaths" == *'@executable_path/../Frameworks'* ]] || die 'helper has no bundle Frameworks rpath'
for path in "$native_build" "$project_root"; do
  [[ "$helper_loads$core_loads$helper_rpaths" != *"$path"* ]] || die "installed Mach-O references build/source path: $path"
done
while IFS= read -r load; do
  case "$load" in
    /System/Library/*|/usr/lib/*|'@rpath/libthread_network_core.dylib'|'@executable_path/'*|'@loader_path/'*) ;;
    '') ;;
    *) die "unbundled native dependency: $load" ;;
  esac
done < <(printf '%s\n%s\n' "$helper_loads" "$core_loads" | awk '/^[[:space:]]/ {print $1}')

if [[ "$mode" == none ]]; then
  printf 'Native helper staged without signing for relocation test: %s\n' "$app"
  exit 0
fi

entitlements="$project_root/app/macos/Runner/Helper.entitlements"
[[ -f "$entitlements" ]] || die "missing helper entitlements: $entitlements"
python3 - "$entitlements" <<'PY' || die 'helper entitlements must contain only sandbox and inherit'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    values = plistlib.load(source)
assert values == {'com.apple.security.app-sandbox': True,
                  'com.apple.security.inherit': True}
PY
parent_entitlements="$project_root/app/macos/Runner/Release.entitlements"
python3 - "$parent_entitlements" <<'PY' || die 'release app requires sandbox and both network entitlements for UDP'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    values = plistlib.load(source)
assert values.get('com.apple.security.app-sandbox') is True
assert values.get('com.apple.security.network.client') is True
assert values.get('com.apple.security.network.server') is True
PY
if [[ "$mode" == developer-id ]]; then
  identity="${TNT_SIGN_IDENTITY:-}"
  [[ "$identity" == 'Developer ID Application: '* ]] || die 'TNT_SIGN_IDENTITY must name a Developer ID Application certificate'
else
  identity='-'
fi
sign_options=(--force --sign "$identity")
if [[ "$mode" == developer-id ]]; then sign_options+=(--options runtime --timestamp); fi

# Sign nested code before the outer bundle. Do not use --deep: it obscures
# which code received the helper's sandbox inheritance entitlement.
while IFS= read -r -d '' dylib; do
  [[ "$dylib" == "$core" ]] && continue
  codesign "${sign_options[@]}" "$dylib"
done < <(find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0)
codesign "${sign_options[@]}" "$core"
while IFS= read -r framework; do
  codesign "${sign_options[@]}" "$framework"
done < <(find "$app/Contents/Frameworks" -type d -name '*.framework' -print | sort -r)
codesign "${sign_options[@]}" --entitlements "$entitlements" "$helper"
codesign "${sign_options[@]}" \
  --entitlements "$parent_entitlements" "$app"
codesign --verify --strict --verbose=2 "$helper"
codesign --verify --deep --strict --verbose=2 "$app"
helper_entitlements="$(codesign -d --entitlements - "$helper" 2>/dev/null)"
[[ "$helper_entitlements" == *'com.apple.security.app-sandbox'* && "$helper_entitlements" == *'com.apple.security.inherit'* ]] || die 'signed helper lacks sandbox inheritance entitlements'
printf 'Staged and %s signed native app: %s\n' "$mode" "$app"
