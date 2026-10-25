#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${TNT_BUILD_DIR:-$project_root/build/native}"
cmake_bin="${TNT_CMAKE_BIN:-cmake}"
"$cmake_bin" -S "$project_root" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release "$@"
"$cmake_bin" --build "$build_dir" --parallel 4
"$cmake_bin" --build "$build_dir" --target test
