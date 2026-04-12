# eta — Swift CLI

This is the canonical AI coding instructions file for this repository. Tool-specific instruction files should import or point here instead of duplicating the guidance.

## Build & Run

```bash
swift build 2>&1 | xcbeautify --is-ci        # debug build
swift build -c release 2>&1 | xcbeautify --is-ci  # release build
swift run eta 'your command here'    # run directly
make install                         # install to /usr/local/bin
```

Always pipe `swift build` output through `xcbeautify` for readable build output.

## Project Structure

```
Sources/
├── ProcessProgress/         # Library target, no ArgumentParser dependency
│   ├── Models.swift         # CommandHistory, Run, LineRecord, command/line hashing
│   ├── HistoryStore.swift   # JSON load/save, pruning, line downsampling
│   ├── CommandRunner.swift  # Process wrapper, line timestamping, normalization
│   ├── LineMatcher.swift    # Exact hash → normalized hash fallback matching
│   ├── EstimateCalculator.swift # Baseline weighted mean ETA and reference offsets
│   └── TimelineProgressEstimator.swift # Cached current-log progress estimation
└── eta-cli/                 # Executable target "eta"
    ├── BarColor+ArgumentParser.swift # ArgumentParser conformance for BarColor
    ├── ETA.swift            # @main, ArgumentParser command, all CLI flags
    └── ProgressRenderer.swift # ANSI progress bar on /dev/tty, TTY detection, BarColor
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

- macOS 13+ / Linux (Swift toolchain)
- Swift 6.0+
- [xcbeautify](https://github.com/cpisciotta/xcbeautify) — `brew install xcbeautify`
- sourcekit-lsp (ships with Xcode) — used for Swift LSP diagnostics

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3+ (SPM)

## Key Design Decisions

- Progress bar writes to the controlling terminal (`/dev/tty`) — wrapped command stdout/stderr stay clean for piping/logging
- Line matching: exact MD5 hash first, normalized fallback (numeric runs collapsed, whitespace collapsed)
- Command keys stored as SHA256 hashes and lines stored as MD5 hashes (not raw text) for privacy — `Insecure.MD5` is fine for line matching (one-way, collisions harmless)
- ETA: exponential weighted mean (α=0.3), recent runs weighted higher via `EstimateCalculator`
- Progress bar: `TimelineProgressEstimator` returns confirmed progress from matched historical lines plus predicted progress from timer projection; renderer draws confirmed as solid fill, predicted-only as shaded fill, and empty progress as spaces; `--solid` draws predicted progress as one solid fill; ETA is based on predicted progress
- Atomic clear→write→redraw under lock prevents timer/output races
- History: JSON files keyed by SHA256 of the command key (`--name` or command string) and storing only that hash
  - macOS: `~/Library/Caches/eta/`
  - Linux: `$XDG_CACHE_HOME/eta/` or `~/.cache/eta/`
- Failed runs (non-zero exit) are not stored
- Lines downsampled to 5000 max (evenly spaced) on save
- Swift 6 strict concurrency throughout

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

1. **EstimateCalculator** computes a baseline expected duration as the exponential weighted mean across all stored runs
2. **LineMatcher** maps each live output line to the reference run (most recent successful run) — exact MD5 hash match first, then normalized hash fallback
3. **TimelineProgressEstimator** tracks the furthest matched reference line ("confirmed" progress) and projects a timer forward from the last correction point ("predicted" progress)
4. **ProgressRenderer** draws the bar on `/dev/tty` at 5 fps, with atomic clear-write-redraw under a lock to prevent races between timer updates and output lines

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

## Git Conventions

- Commit at each logical step (one concern per commit)
- One-line commit messages — short and descriptive

## Maintaining This File

Keep AGENTS.md up to date when making important structural changes: new source files, new dependencies, new CLI flags, changed build steps, or altered design decisions. Don't update for minor refactors or bug fixes.
