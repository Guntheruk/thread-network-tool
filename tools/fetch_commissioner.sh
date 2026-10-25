#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$project_root/vendor/ot-commissioner"
revision=448f807e3246c46e5b82e4cdc12a9b0fb2a646ae
if [[ ! -e "$source_dir" ]]; then
  mkdir -p "$project_root/vendor"
  git clone --no-checkout https://github.com/openthread/ot-commissioner.git "$source_dir"
  git -C "$source_dir" checkout --detach "$revision"
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$revision" ]] || { echo 'Unexpected Commissioner revision; refusing to change checkout.' >&2; exit 1; }
[[ -z "$(git -C "$source_dir" status --porcelain)" ]] || { echo 'Commissioner checkout has local changes; refusing.' >&2; exit 1; }
git -C "$source_dir" submodule update --init --recursive third_party/mbedtls/repo third_party/libevent/repo third_party/fmtlib/repo
printf 'Commissioner ready at %s\n' "$source_dir"
