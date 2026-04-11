# eta — Swift CLI

A command-line tool that learns how long your commands take and shows a live progress bar.

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
│   ├── Models.swift         # CommandHistory, Run, LineRecord, MD5 hashing
│   ├── HistoryStore.swift   # JSON load/save, pruning, line downsampling
│   ├── CommandRunner.swift  # Process wrapper, line timestamping, normalization
│   ├── LineMatcher.swift    # Exact hash → normalized hash fallback matching
│   └── EstimateCalculator.swift # Exponential weighted mean ETA, time-based progress
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
  --quiet                  No progress bar, pure pass-through
  --runs <runs>            History depth (default: 10)
  --list                   List all learned commands
  --stats <command>        Per-line timing breakdown
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
- Line matching: exact MD5 hash first, normalized fallback (digits stripped, whitespace collapsed)
- Lines stored as MD5 hashes (not raw text) for privacy — `Insecure.MD5` is fine here (one-way, collisions harmless)
- ETA: exponential weighted mean (α=0.3), recent runs weighted higher via `EstimateCalculator`
- Progress bar: smooth time-based (`elapsed / expectedTotal`), updated every 100ms via background timer
- Atomic clear→write→redraw under lock prevents timer/output races
- History: JSON files keyed by SHA256 of command string
  - macOS: `~/Library/Caches/eta/`
  - Linux: `$XDG_CACHE_HOME/eta/` or `~/.cache/eta/`
- Failed runs (non-zero exit) are not stored
- Lines downsampled to 5000 max (evenly spaced) on save
- Swift 6 strict concurrency throughout

## Git Conventions

- Commit at each logical step (one concern per commit)
- One-line commit messages — short and descriptive

## Maintaining This File

Keep CLAUDE.md up to date when making important structural changes: new source files, new dependencies, new CLI flags, changed build steps, or altered design decisions. Don't update for minor refactors or bug fixes.
