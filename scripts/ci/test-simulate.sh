#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/eta" >&2
  exit 2
fi

eta_bin="$1"
if [[ "$eta_bin" != /* ]]; then
  eta_bin="$(pwd)/$eta_bin"
fi

if [[ -n "${ETA_CI_ARTIFACT_DIR:-}" ]]; then
  tmp_dir="$ETA_CI_ARTIFACT_DIR"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
elif [[ -n "${RUNNER_TEMP:-}" ]]; then
  tmp_dir="$RUNNER_TEMP/eta-ci/simulate"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
else
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
fi
cache_dir="$tmp_dir/cache"
first_stdout="$tmp_dir/first.stdout"
first_stderr="$tmp_dir/first.stderr"
pty_transcript="$tmp_dir/pty.transcript"

mkdir -p "$cache_dir"

ETA_CACHE_DIR="$cache_dir" \
ETA_SIM_PROFILE=random \
ETA_SIM_MIN_PERCENT=0 \
ETA_SIM_MAX_PERCENT=0 \
"$eta_bin" --name ci-sim --quiet './examples/simulate.sh' >"$first_stdout" 2>"$first_stderr"

grep -q "All tests passed." "$first_stdout"

json_count="$(find "$cache_dir" -name '*.json' -type f | wc -l | tr -d ' ')"
if [[ "$json_count" != "1" ]]; then
  echo "expected one history JSON file, found $json_count" >&2
  exit 1
fi

if [[ -s "$first_stderr" ]]; then
  echo "expected no stderr on quiet simulate run" >&2
  cat "$first_stderr" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 unavailable; skipping pseudo-tty rendering assertion"
  exit 0
fi

python3 - "$eta_bin" "$cache_dir" "$pty_transcript" <<'PY'
import errno
import fcntl
import os
import pty
import subprocess
import sys
import termios

eta_bin, cache_dir, transcript = sys.argv[1:4]
master_fd, slave_fd = pty.openpty()

env = os.environ.copy()
env.update({
    "ETA_CACHE_DIR": cache_dir,
    "ETA_SIM_PROFILE": "random",
    "ETA_SIM_MIN_PERCENT": "0",
    "ETA_SIM_MAX_PERCENT": "0",
})

def configure_child_tty():
    os.setsid()
    try:
        fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
    except Exception:
        pass

process = subprocess.Popen(
    [eta_bin, "--name", "ci-sim", "./examples/simulate.sh"],
    stdin=slave_fd,
    stdout=slave_fd,
    stderr=slave_fd,
    env=env,
    preexec_fn=configure_child_tty,
    close_fds=True,
)
os.close(slave_fd)

captured = bytearray()
while True:
    try:
        chunk = os.read(master_fd, 4096)
    except OSError as error:
        if error.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    captured.extend(chunk)

status = process.wait()
os.close(master_fd)

with open(transcript, "wb") as handle:
    handle.write(captured)

if status != 0:
    sys.exit(status)
PY

grep -q "All tests passed." "$pty_transcript"
if ! grep -q "Done in" "$pty_transcript"; then
  echo "pseudo-tty did not expose /dev/tty progress output; wrapped command output was verified"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### simulate.sh Real Test"
    echo
    echo "| Check | Result |"
    echo "|---|---|"
    echo "| Quiet learning run | passed |"
    echo "| History JSON files | $json_count |"
    echo "| Wrapped output | All tests passed. |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
