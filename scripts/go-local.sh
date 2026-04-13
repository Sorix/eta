#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ETA_GO_BUILD_DIR:-$repo_root/.build/go}"
cache_dir="${ETA_GO_CACHE_DIR:-$build_dir/cache}"
mod_cache_dir="${ETA_GO_MOD_CACHE_DIR:-$build_dir/modcache}"
tmp_dir="${ETA_GO_TMP_DIR:-$build_dir/tmp}"

mkdir -p "$cache_dir" "$mod_cache_dir" "$tmp_dir"

export GOCACHE="${GOCACHE:-$cache_dir}"
export GOMODCACHE="${GOMODCACHE:-$mod_cache_dir}"
export GOTMPDIR="${GOTMPDIR:-$tmp_dir}"

exec "${GO:-go}" "$@"
