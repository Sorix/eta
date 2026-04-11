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
Sources/eta/
├── ETA.swift               # @main, ArgumentParser command, all CLI flags
├── Models.swift            # CommandHistory, Run, LineRecord (Codable)
├── HistoryStore.swift      # JSON load/save to ~/.eta/history/<sha256>.json
├── CommandRunner.swift     # Process wrapper, line timestamping, normalization
├── LineMatcher.swift       # Exact text → normalized fallback matching
├── ETACalculator.swift     # Exponential weighted mean ETA, progress calc
└── ProgressRenderer.swift  # ANSI progress bar on stderr, TTY detection
```

## Requirements

- macOS 13+
- Swift 6.0+
- [xcbeautify](https://github.com/cpisciotta/xcbeautify) — `brew install xcbeautify`
- sourcekit-lsp (ships with Xcode) — used for Swift LSP diagnostics

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3+ (SPM)

## Key Design Decisions

- Progress bar writes to **stderr** — stdout stays clean for piping
- Line matching: exact hash first, normalized fallback (digits stripped, whitespace collapsed)
- ETA: exponential weighted mean (α=0.3), recent runs weighted higher
- History: JSON files keyed by SHA256 of command string
  - macOS: `~/Library/Caches/eta/`
  - Linux: `$XDG_CACHE_HOME/eta/` or `~/.cache/eta/`
- Non-zero exit: saved with `complete: false`, down-weighted in ETA calculation
- Swift 6 strict concurrency throughout

## Git Conventions

- Commit at each logical step (one concern per commit)
- One-line commit messages — short and descriptive

## Maintaining This File

Keep CLAUDE.md up to date when making important structural changes: new source files, new dependencies, new CLI flags, changed build steps, or altered design decisions. Don't update for minor refactors or bug fixes.
