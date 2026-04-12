#!/usr/bin/env bash
set -euo pipefail

if command -v xcbeautify >/dev/null 2>&1; then
  exit 0
fi

install_dir="${HOME}/.local/bin"
work_dir="$(mktemp -d)"
xcbeautify_ref="${XCBEAUTIFY_REF:-3.1.4}"
trap 'rm -rf "$work_dir"' EXIT

git clone --depth 1 --branch "$xcbeautify_ref" https://github.com/cpisciotta/xcbeautify.git "$work_dir/xcbeautify"
swift build -c release --package-path "$work_dir/xcbeautify"

mkdir -p "$install_dir"
cp "$work_dir/xcbeautify/.build/release/xcbeautify" "$install_dir/xcbeautify"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$install_dir" >> "$GITHUB_PATH"
else
  echo "Installed xcbeautify to $install_dir"
fi
