# eta — Swift CLI Implementation Plan

A command-line tool that learns how long your commands take, line by line, and shows a live progress bar on subsequent runs.

## Usage

```bash
eta "make build"
eta --name "ios-build" "xcodebuild -scheme MyApp"
eta --list                  # show all learned commands and run count
eta --clear "make build"    # forget history for a command
eta --stats "make build"    # show timing breakdown per line
eta --quiet "make build"    # no progress bar, pure pass-through
eta --runs 5 "make build"   # use last 5 runs for averaging
```

## Decisions

| Area | Choice |
|---|---|
| Mode | Wrapper only (`eta "command"`) |
| Progress bar | Custom ANSI (no dependency) |
| Colors | Raw ANSI codes (no dependency — already using ANSI for progress bar) |
| Line matching | Exact first, normalized fallback — avoids false matches like `50% complete` vs `100% complete` |
| Storage | JSON in `~/.eta/history/<sha256>.json` |
| ETA averaging | Exponential weighted mean, prune runs older than threshold |
| Argument parser | `swift-argument-parser` by Apple (SPM) |

**Other rules:**
- Show ETA after 1 prior run. First run shows `[learning...]  elapsed: 14s`.
- Max 10 stored runs (configurable `--runs N`). Prune old runs on save.
- Progress bar writes to **stderr**, not stdout — so `eta "cmd" > file.log` works correctly.
- No progress bar if stderr is not a TTY.
- Pass-through: subprocess stdout → stdout, subprocess stderr → stderr; progress bar is a sticky line on stderr.
- Throttle progress bar redraws to ~10-15 fps to avoid flicker on fast output.
- Buffer partial lines (no trailing newline) — don't let the sticky bar overwrite them.
- Non-zero exit: save run but flag as `"complete": false` so ETA calculator can down-weight it.
- On completion: `Done in 47.3s  (expected 45.1s, delta +2.2s)`.

## TODO

### Phase 1: Project Setup
- [ ] `swift package init --type executable --name eta`
- [ ] Add `swift-argument-parser` to `Package.swift`
- [ ] Define `eta --help` output and all flags via ArgumentParser

### Phase 2: Data Model & Storage
- [ ] `Codable` structs: `CommandHistory`, `Run` (with `complete` flag), `LineRecord` (text, normalizedText, offsetSeconds)
- [ ] `HistoryStore` — load/save JSON from `~/.eta/history/`
- [ ] Command fingerprinting: `SHA256(command string)` → filename
- [ ] Prune to last N runs on save; drop runs older than age threshold
- [ ] Handle corrupted/missing files gracefully

### Phase 3: Command Execution
- [ ] Run command via `Process`, pipe stdout+stderr
- [ ] Timestamp each line (`Date()` offset from run start)
- [ ] Handle empty output
- [ ] Handle non-zero exit — save run with `complete: false`

### Phase 4: Line Matching & ETA Calculation
- [ ] `LineMatcher` — exact hash lookup first, then normalized fallback (strip digits/punctuation)
- [ ] `ETACalculator`:
  - Exponential weighted mean of historical `totalDuration`
  - `progress = matchedLineOffset / expectedTotal`
  - `eta = expectedTotal - elapsed`
- [ ] Unmatched lines: time-based interpolation (knowing next expected line arrival time, smoothly animate progress toward it)
- [ ] Handle out-of-order lines; accumulate new lines for future runs

### Phase 5: Terminal Display
- [ ] TTY detection on stderr (`isatty(STDERR_FILENO)`)
- [ ] Progress bar renderer (writes to stderr): `[████████░░░░] 67%  ETA 14s  (5 runs)`
- [ ] Adaptive width — drop components if terminal is narrow
- [ ] Sticky line on stderr: clear bar → print output line (stdout) → redraw bar (stderr)
- [ ] Throttle redraws to ~10-15 fps
- [ ] Buffer partial lines — don't overwrite incomplete output
- [ ] Completion summary: `Done in 47.3s  (expected 45.1s, delta +2.2s)`

### Phase 6: Utility Commands
- [ ] `--list` — table of learned commands, run count, avg duration
- [ ] `--clear "command"` / `--clear --all` — delete history
- [ ] `--stats "command"` — per-line timing breakdown

### Phase 7: Polish & Distribution
- [ ] `Makefile` with `make install` → `/usr/local/bin`
- [ ] Homebrew formula
- [ ] README

## File Structure

```
Sources/eta/
├── ETA.swift               # @main, ArgumentParser command
├── Models.swift            # CommandHistory, Run, LineRecord
├── HistoryStore.swift      # JSON load/save, pruning
├── CommandRunner.swift     # Process wrapper, line timestamping
├── LineMatcher.swift       # Normalized line lookup
├── ETACalculator.swift     # Progress + ETA from history
└── ProgressRenderer.swift  # ANSI progress bar + color helpers, sticky line, TTY check
```

## Dependencies

```swift
.package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
```
