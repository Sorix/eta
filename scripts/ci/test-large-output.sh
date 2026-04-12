#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/eta" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the large-output test" >&2
  exit 1
fi

eta_bin="$1"
if [[ "$eta_bin" != /* ]]; then
  eta_bin="$(pwd)/$eta_bin"
fi

line_count="${ETA_PERF_LINES:-100000}"
max_seconds="${ETA_PERF_MAX_SECONDS:-60}"
if [[ -n "${ETA_CI_ARTIFACT_DIR:-}" ]]; then
  tmp_dir="$ETA_CI_ARTIFACT_DIR"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
elif [[ -n "${RUNNER_TEMP:-}" ]]; then
  tmp_dir="$RUNNER_TEMP/eta-ci/large-output"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
else
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
fi
cache_dir="$tmp_dir/cache"
stdout_file="$tmp_dir/stdout.txt"
stderr_file="$tmp_dir/stderr.txt"
elapsed_file="$tmp_dir/elapsed.txt"

mkdir -p "$cache_dir"

command_text="i=1; while [ \"\$i\" -le $line_count ]; do printf 'ETA_PERF_LINE_%06d\\n' \"\$i\"; i=\$((i + 1)); done"

python3 - "$eta_bin" "$cache_dir" "$command_text" "$stdout_file" "$stderr_file" "$elapsed_file" <<'PY'
import os
import subprocess
import sys
import time

eta_bin, cache_dir, command_text, stdout_file, stderr_file, elapsed_file = sys.argv[1:7]
env = os.environ.copy()
env["ETA_CACHE_DIR"] = cache_dir

start = time.monotonic()
with open(stdout_file, "wb") as stdout, open(stderr_file, "wb") as stderr:
    process = subprocess.run(
        [eta_bin, "--name", "ci-large-output", "--quiet", command_text],
        stdout=stdout,
        stderr=stderr,
        env=env,
        check=False,
    )
elapsed = time.monotonic() - start

with open(elapsed_file, "w", encoding="utf-8") as handle:
    handle.write(f"{elapsed:.6f}\n")

sys.exit(process.returncode)
PY

actual_lines="$(wc -l < "$stdout_file" | tr -d ' ')"
if [[ "$actual_lines" != "$line_count" ]]; then
  echo "expected $line_count stdout lines, found $actual_lines" >&2
  exit 1
fi

if [[ -s "$stderr_file" ]]; then
  echo "expected no stderr from large-output quiet run" >&2
  cat "$stderr_file" >&2
  exit 1
fi

python3 - "$elapsed_file" "$max_seconds" <<'PY'
import sys

elapsed = float(open(sys.argv[1], encoding="utf-8").read())
limit = float(sys.argv[2])
if elapsed > limit:
    raise SystemExit(f"large-output run took {elapsed:.2f}s, limit is {limit:.2f}s")
print(f"large-output run took {elapsed:.2f}s")
PY

history_file="$(find "$cache_dir" -name '*.json' -type f | head -n 1)"
if [[ -z "$history_file" ]]; then
  echo "expected history JSON file" >&2
  exit 1
fi

python3 - "$history_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    history = json.load(handle)

runs = history.get("runs", [])
if len(runs) != 1:
    raise SystemExit(f"expected one saved run, found {len(runs)}")

line_count = len(runs[-1].get("lines", []))
if line_count != 5000:
    raise SystemExit(f"expected 5000 saved lines, found {line_count}")
PY

if grep -q "ETA_PERF_LINE" "$history_file"; then
  echo "history JSON contains raw output text" >&2
  exit 1
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Large Output Performance"
    echo
    echo "| Metric | Value |"
    echo "|---|---:|"
    echo "| Lines emitted | $line_count |"
    echo "| Saved history lines | 5000 |"
    echo "| Elapsed seconds | $(cat "$elapsed_file") |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
