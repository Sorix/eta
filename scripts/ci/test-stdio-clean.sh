#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/eta" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the stdio cleanliness test" >&2
  exit 1
fi

eta_bin="$1"
if [[ "$eta_bin" != /* ]]; then
  eta_bin="$(pwd)/$eta_bin"
fi

line_count="${ETA_STDIO_LINES:-20000}"
max_seconds="${ETA_STDIO_MAX_SECONDS:-60}"
require_tty_progress="${ETA_REQUIRE_TTY_PROGRESS:-${CI:-0}}"
if [[ -n "${ETA_CI_ARTIFACT_DIR:-}" ]]; then
  tmp_dir="$ETA_CI_ARTIFACT_DIR"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
elif [[ -n "${RUNNER_TEMP:-}" ]]; then
  tmp_dir="$RUNNER_TEMP/eta-ci/stdio"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"
else
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
fi
cache_dir="$tmp_dir/cache"
stdout_file="$tmp_dir/stdout.log"
stderr_file="$tmp_dir/stderr.log"
tty_file="$tmp_dir/tty.log"
elapsed_file="$tmp_dir/elapsed.txt"

mkdir -p "$cache_dir"

command_text="i=1; while [ \"\$i\" -le $line_count ]; do printf 'ETA_STDOUT_LINE_%06d\\n' \"\$i\"; printf 'ETA_STDERR_LINE_%06d\\n' \"\$i\" >&2; i=\$((i + 1)); done"

ETA_CACHE_DIR="$cache_dir" "$eta_bin" --name ci-stdio --quiet "$command_text" >"$tmp_dir/seed.stdout" 2>"$tmp_dir/seed.stderr"

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
        [eta_bin, "--name", "ci-stdio", command_text],
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

stdout_lines="$(wc -l < "$stdout_file" | tr -d ' ')"
stderr_lines="$(wc -l < "$stderr_file" | tr -d ' ')"
if [[ "$stdout_lines" != "$line_count" ]]; then
  echo "expected $line_count stdout lines, found $stdout_lines" >&2
  exit 1
fi
if [[ "$stderr_lines" != "$line_count" ]]; then
  echo "expected $line_count stderr lines, found $stderr_lines" >&2
  exit 1
fi

if grep -q "ETA_STDERR_LINE" "$stdout_file"; then
  echo "stderr output leaked into stdout log" >&2
  exit 1
fi
if grep -q "ETA_STDOUT_LINE" "$stderr_file"; then
  echo "stdout output leaked into stderr log" >&2
  exit 1
fi
if grep -q "Done in" "$stdout_file" "$stderr_file"; then
  echo "progress footer leaked into stdout/stderr logs" >&2
  exit 1
fi
if python3 - "$stdout_file" "$stderr_file" <<'PY'
import sys

for path in sys.argv[1:]:
    with open(path, "rb") as handle:
        if b"\x1b[" in handle.read():
            raise SystemExit(1)
PY
then
  :
else
  echo "ANSI progress escape sequence leaked into stdout/stderr logs" >&2
  exit 1
fi

python3 - "$elapsed_file" "$max_seconds" <<'PY'
import sys

elapsed = float(open(sys.argv[1], encoding="utf-8").read())
limit = float(sys.argv[2])
if elapsed > limit:
    raise SystemExit(f"stdio run took {elapsed:.2f}s, limit is {limit:.2f}s")
print(f"stdio run took {elapsed:.2f}s")
PY

python3 - "$eta_bin" "$cache_dir" "$command_text" "$tmp_dir/tty.stdout" "$tmp_dir/tty.stderr" "$tty_file" <<'PY'
import errno
import fcntl
import os
import pty
import select
import subprocess
import sys
import termios

eta_bin, cache_dir, command_text, stdout_file, stderr_file, tty_file = sys.argv[1:7]
master_fd, slave_fd = pty.openpty()
slave_name = os.ttyname(slave_fd)

env = os.environ.copy()
env["ETA_CACHE_DIR"] = cache_dir

def configure_child_tty():
    os.setsid()
    fd = os.open(slave_name, os.O_RDWR)
    try:
        fcntl.ioctl(fd, termios.TIOCSCTTY, 0)
    finally:
        os.close(fd)

captured = bytearray()
try:
    with open(stdout_file, "wb") as stdout, open(stderr_file, "wb") as stderr:
        process = subprocess.Popen(
            [eta_bin, "--name", "ci-stdio", command_text],
            stdin=slave_fd,
            stdout=stdout,
            stderr=stderr,
            env=env,
            preexec_fn=configure_child_tty,
            close_fds=True,
        )
    os.close(slave_fd)

    while True:
        try:
            ready, _, _ = select.select([master_fd], [], [], 0.1)
            if ready:
                chunk = os.read(master_fd, 4096)
                if not chunk:
                    break
                captured.extend(chunk)
            if process.poll() is not None:
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
                break
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise

    status = process.wait()
finally:
    try:
        os.close(master_fd)
    except OSError:
        pass

with open(tty_file, "wb") as handle:
    handle.write(captured)

sys.exit(status)
PY

tty_stdout_lines="$(wc -l < "$tmp_dir/tty.stdout" | tr -d ' ')"
tty_stderr_lines="$(wc -l < "$tmp_dir/tty.stderr" | tr -d ' ')"
if [[ "$tty_stdout_lines" != "$line_count" ]]; then
  echo "expected $line_count pseudo-tty stdout lines, found $tty_stdout_lines" >&2
  exit 1
fi
if [[ "$tty_stderr_lines" != "$line_count" ]]; then
  echo "expected $line_count pseudo-tty stderr lines, found $tty_stderr_lines" >&2
  exit 1
fi

if grep -q "Done in" "$tmp_dir/tty.stdout" "$tmp_dir/tty.stderr"; then
  echo "TTY progress footer leaked into redirected stdout/stderr logs" >&2
  exit 1
fi

if python3 - "$tmp_dir/tty.stdout" "$tmp_dir/tty.stderr" <<'PY'
import sys

for path in sys.argv[1:]:
    with open(path, "rb") as handle:
        if b"\x1b[" in handle.read():
            raise SystemExit(1)
PY
then
  :
else
  echo "TTY progress ANSI escape sequence leaked into redirected stdout/stderr logs" >&2
  exit 1
fi

progress_observed=no
if grep -q "Done in" "$tty_file"; then
  progress_observed=yes
else
  if [[ "$require_tty_progress" == "1" || "$require_tty_progress" == "true" ]]; then
    echo "expected progress output on /dev/tty, but no 'Done in' footer was captured" >&2
    echo "tty transcript: $tty_file" >&2
    exit 1
  fi
  echo "pseudo-tty did not expose /dev/tty progress output; redirected logs were verified"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Stdout/Stderr Cleanliness"
    echo
    echo "| Metric | Value |"
    echo "|---|---:|"
    echo "| Stdout lines | $stdout_lines |"
    echo "| Stderr lines | $stderr_lines |"
    echo "| Pseudo-tty stdout lines | $tty_stdout_lines |"
    echo "| Pseudo-tty stderr lines | $tty_stderr_lines |"
    echo "| Progress observed on TTY | $progress_observed |"
    echo "| Elapsed seconds | $(cat "$elapsed_file") |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
