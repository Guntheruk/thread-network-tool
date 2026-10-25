#!/usr/bin/env bash
set -euo pipefail

die() { printf 'build_macos_app: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || die 'macOS is required'
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
macos_architectures="${TNT_MACOS_ARCHITECTURES:-arm64;x86_64}"
python_bin="$(command -v "${TNT_PYTHON_BIN:-python3}")" || die 'Python unavailable (set TNT_PYTHON_BIN)'
export PYTHONDONTWRITEBYTECODE=1
commissioner_source="$("$python_bin" "$project_root/tools/resolve_commissioner_source.py" \
  --source "$commissioner_source" --output "$native_build/commissioner-source")" || die 'Commissioner preparation or verification failed'
"$python_bin" "$project_root/tools/prepare_commissioner_source.py" --verify-only --output "$commissioner_source"
cmake_args=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
  "-DCMAKE_OSX_ARCHITECTURES=$macos_architectures" -DTNT_BUILD_TESTS=OFF
  -DTNT_WITH_COMMISSIONER=ON -DTNT_BUILD_MOVE_LAB=OFF -DTNT_BUILD_APP_MOVE_LAB=OFF -DTNT_BUILD_MOVE_JOURNAL=OFF
  "-DPython3_EXECUTABLE=$python_bin" "-DTNT_COMMISSIONER_SOURCE=$commissioner_source")
"$cmake_bin" -S "$project_root" -B "$native_build" "${cmake_args[@]}"
"$cmake_bin" --build "$native_build" --config Release --parallel 4
"$python_bin" "$project_root/tools/prepare_commissioner_source.py" --verify-only --output "$commissioner_source"
capabilities="$("$native_build/thread-network" capabilities)" || die 'native capabilities check failed'
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["authenticated_probe"] is True and d["network_writes"] is False' \
  "$capabilities" || die 'native helper is not a read-only authenticated-probe build'
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
for arch in $app_archs; do
  [[ " $helper_archs " == *" $arch "* ]] || \
    die "native helper lacks Flutter app architecture $arch (set TNT_MACOS_ARCHITECTURES)"
done
[[ -d "$output_dir" || ! -e "$output_dir" ]] || die "output path is not a directory: $output_dir"
mkdir -p "$output_dir"
packaged_app="$output_dir/$app_name"
for provenance_file in commissioner-source-provenance.json commissioner-source-manifest.json commissioner-source.patch; do
  [[ ! -e "$output_dir/$provenance_file" ]] || die "provenance output already exists: $provenance_file (choose a fresh TNT_OUTPUT_DIR)"
done
[[ ! -e "$packaged_app" ]] || die "output already exists: $packaged_app (choose a fresh TNT_OUTPUT_DIR)"
stage_root="$(mktemp -d "$output_dir/.stage.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT
stage_app="$stage_root/$app_name"
/usr/bin/ditto "${apps[0]}" "$stage_app"
TNT_CMAKE_BIN="$cmake_bin" TNT_SIGN_IDENTITY="${TNT_SIGN_IDENTITY:-}" \
  "$project_root/tools/bundle_macos_helper.sh" "$native_build" "$stage_app" "$sign_mode"
# Keep build provenance outside the app; native helper payload stays read-only.
"$python_bin" "$project_root/tools/prepare_commissioner_source.py" --verify-only --output "$commissioner_source"
cp "$commissioner_source/tnt-source-provenance.json" "$stage_root/commissioner-source-provenance.json"
cp "$project_root/patches/commissioner/manifest.json" "$stage_root/commissioner-source-manifest.json"
cp "$project_root/patches/commissioner/legacy-wakeup-channel.patch" "$stage_root/commissioner-source.patch"
mv "$stage_app" "$packaged_app"
for provenance_file in commissioner-source-provenance.json commissioner-source-manifest.json commissioner-source.patch; do
  mv "$stage_root/$provenance_file" "$output_dir/$provenance_file"
done
printf 'Package created: %s\n' "$packaged_app"
if [[ "$sign_mode" == local ]]; then
  printf 'Local ad hoc signature only. This app has no trusted Developer ID signature or notarization.\n'
else
  printf 'Developer ID signature checked locally. Notarization and distribution are separate steps.\n'
fi
