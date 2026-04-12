#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/eta" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for the command-key resolution test" >&2
  exit 1
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
  mkdir -p "$RUNNER_TEMP/eta-ci"
  tmp_dir="$(mktemp -d "$RUNNER_TEMP/eta-ci/command-key.XXXXXX")"
else
  tmp_parent="${TMPDIR:-/tmp}"
  mkdir -p "$tmp_parent"
  tmp_dir="$(mktemp -d "$tmp_parent/eta-command-key.XXXXXX")"
  trap 'rm -rf "$tmp_dir"' EXIT
fi

history_count() {
  find "$1" -name '*.json' -type f | wc -l | tr -d ' '
}

assert_history_count() {
  local cache_dir="$1"
  local expected="$2"
  local actual
  actual="$(history_count "$cache_dir")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $expected history files in $cache_dir, found $actual" >&2
    find "$cache_dir" -name '*.json' -type f -print >&2
    exit 1
  fi
}

assert_run_counts() {
  local cache_dir="$1"
  local expected="$2"
  local actual
  actual="$(python3 - "$cache_dir" <<'PY'
import json
import pathlib
import sys

counts = []
for path in pathlib.Path(sys.argv[1]).glob("*.json"):
    with path.open(encoding="utf-8") as handle:
        counts.append(len(json.load(handle).get("runs", [])))
print(",".join(str(count) for count in sorted(counts)))
PY
)"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected sorted run counts '$expected' in $cache_dir, found '$actual'" >&2
    exit 1
  fi
}

make_script() {
  local path="$1"
  local message="$2"
  cat > "$path" <<SCRIPT
#!/usr/bin/env sh
printf '%s\n' '$message'
SCRIPT
  chmod +x "$path"
}

path_case_dir="$tmp_dir/path-case"
path_cache="$path_case_dir/cache"
mkdir -p "$path_case_dir/work/scripts" "$path_case_dir/work/nested" "$path_cache"
make_script "$path_case_dir/work/scripts/task.sh" "path-task"

(
  cd "$path_case_dir/work"
  ETA_CACHE_DIR="$path_cache" "$eta_bin" --quiet './scripts/task.sh --mode path' \
    > "$path_case_dir/first.stdout" 2> "$path_case_dir/first.stderr"
)
(
  cd "$path_case_dir/work/nested"
  ETA_CACHE_DIR="$path_cache" "$eta_bin" --quiet '../scripts/task.sh --mode path' \
    > "$path_case_dir/second.stdout" 2> "$path_case_dir/second.stderr"
)
(
  cd "$path_case_dir/work/nested"
  ETA_CACHE_DIR="$path_cache" "$eta_bin" --quiet "$path_case_dir/work/scripts/task.sh --mode path" \
    > "$path_case_dir/absolute.stdout" 2> "$path_case_dir/absolute.stderr"
)
assert_history_count "$path_cache" 1
assert_run_counts "$path_cache" "3"
(
  cd "$path_case_dir/work/nested"
  ETA_CACHE_DIR="$path_cache" "$eta_bin" --clear '../scripts/task.sh --mode path' >/dev/null
)
assert_history_count "$path_cache" 0

cwd_case_dir="$tmp_dir/cwd-case"
cwd_cache="$cwd_case_dir/cache"
mkdir -p "$cwd_case_dir/bin" "$cwd_case_dir/project-a" "$cwd_case_dir/project-b" "$cwd_cache"
make_script "$cwd_case_dir/bin/eta-key-task" "cwd-task"

(
  cd "$cwd_case_dir/project-a"
  PATH="$cwd_case_dir/bin:$PATH" ETA_CACHE_DIR="$cwd_cache" "$eta_bin" --quiet 'eta-key-task shared' \
    > "$cwd_case_dir/project-a.stdout" 2> "$cwd_case_dir/project-a.stderr"
)
(
  cd "$cwd_case_dir/project-b"
  PATH="$cwd_case_dir/bin:$PATH" ETA_CACHE_DIR="$cwd_cache" "$eta_bin" --quiet 'eta-key-task shared' \
    > "$cwd_case_dir/project-b.stdout" 2> "$cwd_case_dir/project-b.stderr"
)
assert_history_count "$cwd_cache" 2
assert_run_counts "$cwd_cache" "1,1"

path_lookup_dir="$tmp_dir/path-lookup-case"
path_lookup_cache="$path_lookup_dir/cache"
mkdir -p "$path_lookup_dir/bin-a" "$path_lookup_dir/bin-b" "$path_lookup_dir/project" "$path_lookup_cache"
make_script "$path_lookup_dir/bin-a/eta-key-switch" "path-a"
make_script "$path_lookup_dir/bin-b/eta-key-switch" "path-b"

(
  cd "$path_lookup_dir/project"
  PATH="$path_lookup_dir/bin-a:$PATH" ETA_CACHE_DIR="$path_lookup_cache" "$eta_bin" --quiet 'eta-key-switch shared' \
    > "$path_lookup_dir/bin-a-first.stdout" 2> "$path_lookup_dir/bin-a-first.stderr"
)
(
  cd "$path_lookup_dir/project"
  PATH="$path_lookup_dir/bin-b:$PATH" ETA_CACHE_DIR="$path_lookup_cache" "$eta_bin" --quiet 'eta-key-switch shared' \
    > "$path_lookup_dir/bin-b.stdout" 2> "$path_lookup_dir/bin-b.stderr"
)
(
  cd "$path_lookup_dir/project"
  PATH="$path_lookup_dir/bin-a:$PATH" ETA_CACHE_DIR="$path_lookup_cache" "$eta_bin" --quiet 'eta-key-switch shared' \
    > "$path_lookup_dir/bin-a-second.stdout" 2> "$path_lookup_dir/bin-a-second.stderr"
)
assert_history_count "$path_lookup_cache" 2
assert_run_counts "$path_lookup_cache" "1,2"

nonempty_stderr="$(find "$tmp_dir" -name '*.stderr' -type f -size +0 -print)"
if [[ -n "$nonempty_stderr" ]]; then
  echo "expected command-key integration runs to keep stderr empty" >&2
  echo "$nonempty_stderr" >&2
  exit 1
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Command Key Resolution"
    echo
    echo "| Check | Result |"
    echo "|---|---|"
    echo "| Same script from relative and absolute paths | shared history |"
    echo "| Same PATH command from different cwd | separate histories |"
    echo "| Same command name with different PATH resolution | separate histories |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
