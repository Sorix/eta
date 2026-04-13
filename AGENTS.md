# eta — Go CLI

This is the canonical AI coding instructions file for this repository. Tool-specific instruction files should import or point here instead of duplicating the guidance.

## Build & Run

```bash
make build                           # Go release-style binary at .build/go/eta
make go-test                         # Go unit tests
make go-vet                          # Go vet with repo-local cache/tmp dirs
make go-race                         # Go race-sensitive suites
make check                           # format/test/vet/race/build
scripts/go-local.sh test ./...       # direct Go command with repo-local build/module/tmp dirs
scripts/go-local.sh test -race ./internal/process ./internal/render ./internal/coordinator ./internal/eta
scripts/go-local.sh vet ./...
test -z "$(gofmt -l $(git ls-files '*.go'))"
scripts/ci/test-simulate.sh .build/go/eta      # real simulate.sh test
scripts/ci/test-large-output.sh .build/go/eta  # large-output performance test
scripts/ci/test-stdio-clean.sh .build/go/eta   # stdout/stderr cleanliness test
.build/go/eta 'your command here'    # run built Go binary directly
make install                         # install Go binary to conventional user prefix
sudo make install                    # system install when PREFIX requires privileges
```

CI runs Go unit/format/vet/race/dependency/vulnerability checks and Go integration scripts on Linux and macOS pull request jobs.

## Project Structure

```
cmd/eta/                     # Thin executable target; calls eta.Main(os.Args[1:])
internal/
├── eta/                     # production wiring and exit-code boundary
├── cli/                     # pflag parsing and validation
├── commandkey/              # stable command-key resolution
├── coordinator/             # history/run/render workflow orchestration
├── hashline/                # line normalization and MD5/SHA-256 hashing
├── history/                 # JSON load/save, pruning, downsampling, clear
├── process/                 # shell runner, stream draining, line buffering, raw pass-through
├── progress/                # matcher, reference timeline, ETA estimator
├── render/                  # /dev/tty, formatter, redraw locking, ticker loop, signals
└── testutil/                # test support
testdata/swift-compat/       # compatibility fixtures from the Swift implementation
scripts/ci/                  # GitHub Actions real/e2e and performance test scripts
```

## CLI Flags

```
eta <command>              Run a command with progress tracking
  --name <name>            Custom alias for the command fingerprint
  --color <color>          Bar color: green, yellow, red, blue, magenta, cyan, white
  --quiet                  Learn execution time without showing a progress bar
  --solid                  Draw a single solid fill instead of shading predicted progress
  --runs <runs>            History depth (default: 10)
  --clear <command>        Clear history for a command
  --clear-all              Clear all history
```

## Requirements

- macOS / Linux
- Go 1.26+

## Dependencies

- [github.com/spf13/pflag](https://github.com/spf13/pflag) for CLI parsing
- [golang.org/x/term](https://pkg.go.dev/golang.org/x/term) for terminal detection and width
- [github.com/google/renameio/v2](https://github.com/google/renameio) for atomic history replacement

Repo entrypoints use `scripts/go-local.sh`, which sets repo-local `GOCACHE`, `GOMODCACHE`, and `GOTMPDIR` under `.build/go/` so builds/tests don’t depend on writable user-level Go caches.

## Key Design Decisions

- Progress bar writes to the controlling terminal (`/dev/tty`) — wrapped command stdout/stderr stay clean for piping/logging
- Line matching: exact MD5 hash first, normalized fallback (numeric runs collapsed, whitespace collapsed)
- Command keys stored as SHA256 hashes and lines stored as MD5 hashes (not raw text) for privacy; MD5 is fine for line matching because collisions are harmless here
- ETA: exponential weighted mean (α=0.3), recent runs weighted higher via `ReferenceTimeline`
- Progress bar: `TimelineProgressEstimator` returns confirmed progress from matched historical lines plus predicted progress from timer projection; renderer draws confirmed as solid fill, predicted-only as shaded fill, and empty progress as spaces; `--solid` draws predicted progress as one solid fill; ETA is based on predicted progress
- First run: before a command has usable history, a one-shot yellow header is printed to `/dev/tty` at the top, then command output flows normally without a progress bar; this header intentionally ignores `--color`
- Atomic clear→write→redraw under lock prevents timer/output races
- Command key resolution: when no `--name` is given, the first token is resolved to build a stable key. Path-based invocations (`./test.sh`, `../build.sh`) are canonicalized via `filepath.EvalSymlinks`/absolute path resolution. Bare-name invocations (`make`, `swift build`) are resolved via `/usr/bin/which` and prefixed with the working directory, since the same executable in different projects does different work. Shell aliases, functions, and builtins can't be resolved, so they are treated like bare names (cwd-prefixed).
- History: JSON files keyed by SHA256 of the command key (`--name` or resolved command string) and storing only that hash
  - macOS: `~/Library/Caches/eta/`
  - Linux: `$XDG_CACHE_HOME/eta/` or `~/.cache/eta/`
- Tests and CI may set `ETA_CACHE_DIR` to isolate history files in a temporary directory; this is a hidden test hook, not a user-facing CLI flag
- Failed runs (non-zero exit) are not stored
- Lines downsampled to 5000 max (evenly spaced) on save
- Signal handling restores defaults and re-raises `SIGINT`/`SIGTERM` after render cleanup

## Progress Estimation Pipeline

```
Historical runs          Current run
─────────────           ───────────
┌─────────────┐         ┌──────────┐
│ Run N (most │         │ Live     │
│ recent =    │────┐    │ output   │
│ reference)  │    │    │ stream   │
└─────────────┘    │    └────┬─────┘
                   ▼         │
┌─────────────┐  ┌──────────▼──────┐
│ Weighted    │  │  LineMatcher    │
│ mean ETA    │  │  exact hash →   │
│ (α = 0.3)  │  │  normalized     │
│ from all    │  │  fallback       │
│ runs        │  └──────────┬──────┘
└──────┬──────┘             │
       │              ┌─────▼──────┐
       └──────────────►  Timeline  │
                      │  Progress  │
                      │  Estimator │
                      └─────┬──────┘
                            │
                      ┌─────▼──────┐
                      │  Progress  │
                      │  Renderer  │
                      │  (/dev/tty)│
                      └────────────┘
```

1. **ReferenceTimeline** computes a baseline expected duration as the exponential weighted mean across all stored runs
2. **LineMatcher** maps each live output line to the reference run (most recent successful run) — exact MD5 hash match first, then normalized hash fallback
3. **TimelineProgressEstimator** tracks the furthest matched reference line ("confirmed" progress) and projects a timer forward from the last correction point ("predicted" progress)
4. **ProgressRenderer** draws the bar or first-run status on `/dev/tty` at a 32 ms cadence, with atomic clear-write-redraw under a lock to prevent races between timer updates and output lines

## Privacy Model

History files reveal nothing about what commands you run or what they output:

| Data | Stored as | Algorithm | Reversible? |
|------|-----------|-----------|-------------|
| Command key | `filename.json` | SHA-256 | No |
| Output lines | `textHash`, `normalizedHash` | MD5 | No |

Only timing data (timestamps, durations, dates) is stored in plaintext.

## Line Normalization

Before the fallback hash, lines are normalized:

| Original | Normalized |
|----------|------------|
| `[3/100] Compiling Foo.swift` | `[N/N] Compiling Foo.swift` |
| `Step  5  of  20` | `Step N of N` |
| `Downloaded   128 MB` | `Downloaded N MB` |

All digit runs collapse to `N`. All whitespace runs collapse to a single space.

## Maintaining This File

Keep AGENTS.md up to date when making important structural changes: new source files, new dependencies, new CLI flags, changed build steps, or altered design decisions. Don't update for minor refactors or bug fixes.
