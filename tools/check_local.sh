#!/usr/bin/env bash
# Local checks only. No discovery, household credentials, or hosted jobs.
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmake_bin="${TNT_CMAKE_BIN:-cmake}"
ctest_bin="${TNT_CTEST_BIN:-$(dirname "$(command -v "$cmake_bin")")/ctest}"
python_bin="${TNT_PYTHON_BIN:-python3}"
flutter_bin="${TNT_FLUTTER_BIN:-$project_root/.tooling/flutter/bin/flutter}"
dart_bin="${TNT_DART_BIN:-$(dirname "$flutter_bin")/cache/dart-sdk/bin/dart}"
build_dir="${TNT_CHECK_BUILD_DIR:-$project_root/build/local-checks}"
[[ "$build_dir" = /* ]] || { printf 'Use an absolute TNT_CHECK_BUILD_DIR.\n' >&2; exit 1; }
export PYTHONDONTWRITEBYTECODE=1

options=(-DCMAKE_BUILD_TYPE=Release -DTNT_BUILD_TESTS=ON
  -DTNT_BUILD_MOVE_JOURNAL=ON -DTNT_BUILD_MOVE_LAB=OFF -DTNT_BUILD_APP_MOVE_LAB=OFF)
if [[ -n "${TNT_COMMISSIONER_SOURCE:-}" ]]; then
  source_dir="$("$python_bin" "$project_root/tools/resolve_commissioner_source.py" \
    --source "$TNT_COMMISSIONER_SOURCE" --output "$build_dir/commissioner-source")"
  options+=(-DTNT_WITH_COMMISSIONER=ON "-DTNT_COMMISSIONER_SOURCE=$source_dir"
    "-DPython3_EXECUTABLE=$(command -v "$python_bin")")
else
  options+=(-DTNT_WITH_COMMISSIONER=OFF)
fi
"$cmake_bin" -S "$project_root" -B "$build_dir" "${options[@]}"
"$cmake_bin" --build "$build_dir" --parallel 2
"$ctest_bin" --test-dir "$build_dir" --output-on-failure
if [[ -n "${source_dir:-}" ]]; then
  "$python_bin" "$project_root/tools/prepare_commissioner_source.py" --verify-only --output "$source_dir"
fi

export TNT_JOURNAL_CLI="$build_dir/thread-move-journal"
export TNT_JOURNAL_FAULT="$build_dir/tnt-move-journal-fault"
cd "$project_root"
"$python_bin" -m unittest discover -s tests/tools -v
cd "$project_root/app"
"$flutter_bin" pub get
"$flutter_bin" analyze --no-pub
"$flutter_bin" test --no-pub
"$dart_bin" run tool/network_move_plan_test.dart
"$dart_bin" run tool/network_move_api_test.dart
"$dart_bin" run tool/local_server_test.dart
"$dart_bin" run tool/move_execution_test.dart "$TNT_JOURNAL_CLI"
printf 'Local checks passed. Platform builds and isolated app moves are separate evidence.\n'
