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
mac_alpha="${TNT_MAC_ALPHA:-0}"
[[ "$mac_alpha" == 0 || "$mac_alpha" == 1 ]] || die 'TNT_MAC_ALPHA must be 0 or 1'
helpers="$app/Contents/Helpers"
rm -f "$helpers/thread-network" "$helpers/tnt-mac-move-worker" \
  "$helpers/thread-move-journal" "$helpers/thread-network-move-app" \
  "$helpers/thread-network-move-lab" "$helpers/tnt-move-journal-fault" \
  "$app/Contents/Frameworks/libthread_network_core.dylib"
"$cmake_bin" --install "$native_build" --prefix "$app/Contents"
helper="$helpers/thread-network"
core="$app/Contents/Frameworks/libthread_network_core.dylib"
[[ -x "$helper" && -f "$core" ]] || die 'CMake install omitted the native helper or core'
for forbidden in thread-network-move-app thread-network-move-lab tnt-move-journal-fault; do
  [[ ! -e "$helpers/$forbidden" && ! -L "$helpers/$forbidden" ]] || die "isolated move fixture installed: $forbidden"
done
if [[ "$mac_alpha" == 1 ]]; then
  for move_helper in "$helpers/tnt-mac-move-worker" "$helpers/thread-move-journal"; do
    [[ -x "$move_helper" ]] || die "Mac alpha helper missing after install: $move_helper"
  done
  installed_capabilities="$("$helpers/tnt-mac-move-worker" capabilities)" || die 'installed Mac alpha worker capabilities check failed'
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert type(d) is dict and d == {"schema_version":1,"profile_id":"eero-source-network-alpha-v1","network_writes":True,"authenticated_reads":True,"durable_fence":True}' \
    "$installed_capabilities" || die 'installed Mac alpha worker capabilities are invalid'
else
  for forbidden in tnt-mac-move-worker thread-move-journal; do
    [[ ! -e "$helpers/$forbidden" && ! -L "$helpers/$forbidden" ]] || die "move helper installed in read-only package: $forbidden"
  done
fi
app_executable="$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")"
app_archs="$(lipo -archs "$app/Contents/MacOS/$app_executable")"
[[ -n "$app_archs" ]] || die 'app architecture list is empty'
for native_helper in "$helper" "$helpers/tnt-mac-move-worker" "$helpers/thread-move-journal"; do
  [[ "$native_helper" == "$helper" || "$mac_alpha" == 1 ]] || continue
  helper_archs="$(lipo -archs "$native_helper")"
  [[ -n "$helper_archs" ]] || die "installed $(basename "$native_helper") architecture list is empty"
  for arch in $app_archs; do
    [[ " $helper_archs " == *" $arch "* ]] || die "installed $(basename "$native_helper") lacks app architecture $arch"
  done
done

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
for move_helper in "$helpers/tnt-mac-move-worker" "$helpers/thread-move-journal"; do
  [[ "$mac_alpha" == 1 ]] || break
  move_loads="$(otool -L "$move_helper" | awk '/^[[:space:]]/ {print}')"
  move_rpaths="$(otool -l "$move_helper" | awk '/cmd LC_RPATH/{found=1;next} found && /path /{print $2;found=0}')"
  [[ "$move_loads" != *'@rpath/libthread_network_core.dylib'* || "$move_rpaths" == *'@executable_path/../Frameworks'* ]] || die "move helper has no bundle Frameworks rpath: $move_helper"
  for path in "$native_build" "$project_root"; do
    [[ "$move_loads$move_rpaths" != *"$path"* ]] || die "installed move helper references build/source path: $path"
  done
  while IFS= read -r load; do
    case "$load" in
      /System/Library/*|/usr/lib/*|'@rpath/libthread_network_core.dylib'|'@executable_path/../Frameworks/'*|'@loader_path/../Frameworks/'*|'') ;;
      *) die "unbundled move helper dependency: $load" ;;
    esac
  done < <(printf '%s\n' "$move_loads" | awk '/^[[:space:]]/ {print $1}')
done
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
for move_helper in "$helpers/tnt-mac-move-worker" "$helpers/thread-move-journal"; do
  [[ "$mac_alpha" == 1 ]] || break
  codesign "${sign_options[@]}" --entitlements "$entitlements" "$move_helper"
done
codesign "${sign_options[@]}" \
  --entitlements "$parent_entitlements" "$app"
codesign --verify --strict --verbose=2 "$helper"
for move_helper in "$helpers/tnt-mac-move-worker" "$helpers/thread-move-journal"; do
  [[ "$mac_alpha" == 1 ]] || break
  codesign --verify --strict --verbose=2 "$move_helper"
  move_entitlements="$(codesign -d --entitlements - "$move_helper" 2>/dev/null)"
  [[ "$move_entitlements" == *'com.apple.security.app-sandbox'* && "$move_entitlements" == *'com.apple.security.inherit'* ]] || die "signed move helper lacks sandbox inheritance entitlements: $move_helper"
done
codesign --verify --deep --strict --verbose=2 "$app"
helper_entitlements="$(codesign -d --entitlements - "$helper" 2>/dev/null)"
[[ "$helper_entitlements" == *'com.apple.security.app-sandbox'* && "$helper_entitlements" == *'com.apple.security.inherit'* ]] || die 'signed helper lacks sandbox inheritance entitlements'
printf 'Staged and %s signed native app: %s\n' "$mode" "$app"
