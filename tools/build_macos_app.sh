#!/usr/bin/env bash
set -euo pipefail

die() { printf 'build_macos_app: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || die 'macOS is required'
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mac_alpha="${TNT_MAC_ALPHA:-0}"
[[ "$mac_alpha" == 0 || "$mac_alpha" == 1 ]] || die 'TNT_MAC_ALPHA must be 0 or 1'
export TNT_MAC_ALPHA="$mac_alpha"

# Flutter's macOS build needs the full Xcode app. Do this before resolving
# dependencies or creating any build output.
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
[[ -n "$developer_dir" && "$developer_dir" != */CommandLineTools ]] || \
  die 'full Xcode is required; DEVELOPER_DIR or the active developer directory points to Command Line Tools. Select full Xcode for this command, then rerun.'
xcodebuild -version >/dev/null 2>&1 || die 'xcodebuild is unavailable from the active full Xcode installation'
xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || die 'Xcode macOS SDK is unavailable'

cmake_bin="${TNT_CMAKE_BIN:-cmake}"
flutter_bin="${TNT_FLUTTER_BIN:-$project_root/.tooling/flutter/bin/flutter}"
[[ -x "$cmake_bin" ]] || command -v "$cmake_bin" >/dev/null 2>&1 || die "CMake unavailable: $cmake_bin (set TNT_CMAKE_BIN)"
[[ -x "$flutter_bin" ]] || die "Flutter SDK unavailable: $flutter_bin (set TNT_FLUTTER_BIN)"
commissioner_source="${TNT_COMMISSIONER_SOURCE:-}"
[[ -n "$commissioner_source" && -f "$commissioner_source/CMakeLists.txt" ]] || \
  die 'set TNT_COMMISSIONER_SOURCE to the pinned OpenThread Commissioner checkout or verified generated source for live read support'
sign_mode="${TNT_SIGN_MODE:-local}"
[[ "$sign_mode" == local || "$sign_mode" == developer-id ]] || die 'TNT_SIGN_MODE must be local or developer-id'
if [[ "$sign_mode" == developer-id ]]; then
  [[ "${TNT_SIGN_IDENTITY:-}" == 'Developer ID Application: '* ]] || \
    die 'set TNT_SIGN_IDENTITY to a Developer ID Application certificate for developer-id mode'
fi

native_build="${TNT_NATIVE_BUILD_DIR:-$project_root/build/macos-native-package}"
output_dir="${TNT_OUTPUT_DIR:-$project_root/build/macos-package}"
# One fresh package directory is the publication unit. Never extend an earlier
# app/provenance/notices set, even if the existing directory appears empty.
[[ ! -e "$output_dir" && ! -L "$output_dir" ]] || die "output already exists: $output_dir (choose a fresh TNT_OUTPUT_DIR)"
macos_architectures="${TNT_MACOS_ARCHITECTURES:-arm64;x86_64}"
python_bin="$(command -v "${TNT_PYTHON_BIN:-python3}")" || die 'Python unavailable (set TNT_PYTHON_BIN)'
export PYTHONDONTWRITEBYTECODE=1
flutter_root="$("$python_bin" -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().parent.parent)' "$flutter_bin")"
commissioner_source="$("$python_bin" "$project_root/tools/resolve_commissioner_source.py" \
  --source "$commissioner_source" --output "$native_build/commissioner-source")" || die 'Commissioner preparation or verification failed'
"$python_bin" "$project_root/tools/prepare_commissioner_source.py" --verify-only --output "$commissioner_source"
move_build=OFF
if [[ "$mac_alpha" == 1 ]]; then move_build=ON; fi
cmake_args=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
  "-DCMAKE_OSX_ARCHITECTURES=$macos_architectures" -DTNT_BUILD_TESTS=OFF
  -DTNT_WITH_COMMISSIONER=ON -DTNT_BUILD_MOVE_LAB=OFF -DTNT_BUILD_APP_MOVE_LAB=OFF
  "-DTNT_BUILD_MAC_MOVE_WORKER=$move_build" "-DTNT_BUILD_MOVE_JOURNAL=$move_build"
  "-DPython3_EXECUTABLE=$python_bin" "-DTNT_COMMISSIONER_SOURCE=$commissioner_source")
"$cmake_bin" -S "$project_root" -B "$native_build" "${cmake_args[@]}"
"$cmake_bin" --build "$native_build" --config Release --parallel 4
"$python_bin" "$project_root/tools/prepare_commissioner_source.py" --verify-only --output "$commissioner_source"
capabilities="$("$native_build/thread-network" capabilities)" || die 'native capabilities check failed'
"$python_bin" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["authenticated_probe"] is True and d["network_writes"] is False' \
  "$capabilities" || die 'native helper is not a read-only authenticated-probe build'
if [[ "$mac_alpha" == 1 ]]; then
  [[ -x "$native_build/tnt-mac-move-worker" ]] || die 'Mac alpha worker executable missing'
  [[ -x "$native_build/thread-move-journal" ]] || die 'Mac alpha journal executable missing'
  worker_capabilities="$("$native_build/tnt-mac-move-worker" capabilities)" || die 'Mac alpha worker capabilities check failed'
  "$python_bin" -c 'import json,sys; d=json.loads(sys.argv[1]); assert type(d) is dict and d == {"schema_version":1,"profile_id":"eero-source-network-alpha-v1","network_writes":True,"authenticated_reads":True,"durable_fence":True}' \
    "$worker_capabilities" || die 'Mac alpha worker capabilities are invalid'
fi
(cd "$project_root/app" && "$flutter_bin" build macos --release)

products="$project_root/app/build/macos/Build/Products/Release"
[[ -d "$products" ]] || die "Flutter release product directory missing: $products"
shopt -s nullglob
apps=("$products"/*.app)
[[ ${#apps[@]} == 1 ]] || die "expected exactly one Flutter release .app in $products; found ${#apps[@]}"
app_name="$(basename "${apps[0]}")"
app_executable="$(plutil -extract CFBundleExecutable raw "${apps[0]}/Contents/Info.plist")"
[[ -x "${apps[0]}/Contents/MacOS/$app_executable" ]] || die 'Flutter app executable missing'
app_archs="$(lipo -archs "${apps[0]}/Contents/MacOS/$app_executable")"
helper_archs="$(lipo -archs "$native_build/thread-network")"
[[ -n "$app_archs" && -n "$helper_archs" ]] || die 'app or native helper architecture list is empty'
for arch in $app_archs; do
  [[ " $helper_archs " == *" $arch "* ]] || \
    die "native helper lacks Flutter app architecture $arch (set TNT_MACOS_ARCHITECTURES)"
done
if [[ "$mac_alpha" == 1 ]]; then
  for move_helper in tnt-mac-move-worker thread-move-journal; do
    move_archs="$(lipo -archs "$native_build/$move_helper")"
    [[ -n "$move_archs" ]] || die "$move_helper architecture list is empty"
    for arch in $app_archs; do
      [[ " $move_archs " == *" $arch "* ]] || die "$move_helper lacks Flutter app architecture $arch"
    done
  done
fi
output_parent="$(dirname "$output_dir")"
output_name="$(basename "$output_dir")"
mkdir -p "$output_parent"
stage_root="$(mktemp -d "$output_parent/.$output_name.stage.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT
packaged_app="$output_dir/$app_name"
stage_app="$stage_root/$app_name"
/usr/bin/ditto "${apps[0]}" "$stage_app"
TNT_CMAKE_BIN="$cmake_bin" TNT_SIGN_IDENTITY="${TNT_SIGN_IDENTITY:-}" \
  "$project_root/tools/bundle_macos_helper.sh" "$native_build" "$stage_app" "$sign_mode"
# Keep build provenance outside the app.
"$python_bin" "$project_root/tools/prepare_commissioner_source.py" --verify-only --output "$commissioner_source"
cp "$commissioner_source/tnt-source-provenance.json" "$stage_root/commissioner-source-provenance.json"
cp "$project_root/patches/commissioner/manifest.json" "$stage_root/commissioner-source-manifest.json"
cp "$project_root/patches/commissioner/legacy-wakeup-channel.patch" "$stage_root/commissioner-source.patch"
# Collect from the actual just-built/signed app, using this build's verified
# dependency and selected toolchain. Collector status 1 records gaps; status 2
# records a collection failure. Neither is a publishable package.
flutter_notices="$stage_app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/NOTICES.Z"
notice_status=0
"$python_bin" "$project_root/tools/collect_third_party_notices.py" \
  --output-dir "$stage_root/release-notices" --app-root "$project_root/app" \
  --commissioner-root "$commissioner_source" --flutter-root "$flutter_root" \
  --flutter-notices "$flutter_notices" >"$stage_root/notice-collection.log" 2>&1 || notice_status=$?
if [[ "$notice_status" != 0 ]]; then
  # Preserve incomplete manifests and fixed failure diagnostics separately,
  # without retaining an app that could be mistaken for a complete package.
  failure_root="$(mktemp -d "$output_parent/.$output_name.notices-failed.XXXXXX")"
  if [[ -d "$stage_root/release-notices" ]]; then
    mv "$stage_root/release-notices" "$failure_root/release-notices"
  fi
  mv "$stage_root/notice-collection.log" "$failure_root/notice-collection.log"
  printf '%s\n' "$notice_status" >"$failure_root/collector-exit-status.txt"
  die "notice collection incomplete or failed; no package published. Evidence: $failure_root"
fi
[[ -f "$stage_root/release-notices/MANIFEST.md" ]] || die 'notice collector did not produce a manifest'
# Publish all artifacts together using Darwin's exclusive atomic rename.
# RENAME_EXCL also refuses an empty directory/symlink created by another writer
# after our preflight; a check followed by ordinary rename would race.
"$python_bin" - "$stage_root" "$output_dir" <<'PYTHON'
import ctypes
import os
import sys
rename = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True).renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
# macOS sys/stdio.h: RENAME_EXCL = 0x00000004 (macOS 10.12+).
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 0x00000004):
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
PYTHON
printf 'Package created: %s\n' "$packaged_app"
if [[ "$sign_mode" == local ]]; then
  printf 'Local ad hoc signature only. This app has no trusted Developer ID signature or notarization.\n'
else
  printf 'Developer ID signature checked locally. Notarization and distribution are separate steps.\n'
fi
