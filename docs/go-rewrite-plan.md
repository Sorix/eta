# Go Rewrite Plan

Rewrite `eta` in Go as a small, high-quality CLI utility. Preserve behavior and history compatibility first; improve implementation quality through Go idioms, clear package boundaries, and strong tests.

Status: Go cutover is complete. The Swift implementation has been removed after approved cutover; Swift references below are historical compatibility context or fixture provenance.

## Goals

- One static Go binary with fast startup.
- Clean stdout/stderr for wrapped commands; progress only on `/dev/tty`.
- Existing history files remain readable.
- Small internal packages with obvious ownership.
- Dependencies only when they remove real complexity.
- Agent-friendly task slices with non-overlapping write scopes.

## Parity Contract

The Go binary must preserve:

- CLI flags: `--name`, `--color`, `--quiet`, `--solid`, `--runs`, `--clear`, `--clear-all`, and positional `<command>`.
- Exactly one mode at a time: run, clear one, or clear all.
- Wrapped command execution through `$SHELL -c <command>` or `/bin/sh -c <command>`.
- Wrapped stdout/stderr pass through unchanged and remain separate.
- Progress and final status write only to `/dev/tty`.
- Non-quiet first run with no history writes the yellow header and no progress bar; `--quiet` suppresses that header while still saving successful history.
- Non-zero wrapped command exits with the same code and does not save history.
- Successful runs save history even when quiet or rendering is disabled.
- History directory: `ETA_CACHE_DIR`, otherwise user cache dir plus `eta`.
- History privacy: SHA-256 command-key filenames; MD5 line hashes; no raw command/output text.
- JSON schema: `runs`, `date`, `totalDuration`, `lines`, `textHash`, `normalizedHash`, `offsetSeconds`.
- Run retention by `--runs`; line downsampling to 5000, keeping first and last line.
- Stale JSON pruning after saves, default 90 days.
- Line normalization: digit runs to `N`, whitespace runs to one space, trim edges.
- Matching: newest successful run as reference, exact hash first, normalized fallback, repeated lines only after previous match.
- ETA math: alpha `0.3`, newest-first weighted mean, confirmed plus predicted progress, slow milestones extend adjusted duration.

## Target Structure

Use one module, internal packages, and no exported public API in the first rewrite.

```text
go.mod
go.sum
cmd/eta/
  main.go
internal/eta/
  app.go                 # production wiring and exit-code boundary
  errors.go              # typed exit/status errors
internal/cli/
  parse.go               # pflag parsing into request structs
internal/commandkey/
  key.go
  key_unix.go
internal/hashline/
  hash.go
  normalize.go
internal/progress/
  types.go
  matcher.go
  timeline.go
  estimator.go
internal/history/
  store.go
internal/process/
  runner.go
  linebuffer.go
  writer.go
internal/render/
  color.go
  formatter.go
  renderer.go
  terminal_unix.go
  loop.go
  signals_unix.go
internal/coordinator/
  coordinator.go
  session.go
internal/testutil/
  fixtures.go            # tests only
testdata/swift-compat/
scripts/ci/
```

Rules:

- `cmd/eta` only calls `eta.Main(os.Args[1:])` and `os.Exit`.
- `internal/eta` owns dependency wiring and user-facing stderr messages.
- `internal/coordinator` owns workflow orchestration and defines narrow consumer-side interfaces.
- `internal/progress` stays pure: no filesystem, terminal, process, CLI, or environment imports.
- `internal/process` owns `os/exec`, stream draining, line buffering, and raw output pass-through.
- `internal/render` owns `/dev/tty`, formatting, redraw locking, ticker loop, cursor cleanup, and signals.
- Do not create `pkg`, `models`, `utils`, `common`, or `helpers`.
- Split packages only when it helps ownership, tests, or platform boundaries.

## Dependencies

Checked against upstream package metadata on 2026-04-13.

| Area | Decision | License / maintenance note |
| --- | --- | --- |
| CLI flags | Use `github.com/spf13/pflag`. Small and enough for a single-command wrapper. | BSD-3-Clause, stable v1 module, broadly used. |
| CLI frameworks | Do not use Cobra or Kong in MVP. Reconsider only if real subcommands are added. | Avoids framework dependency until the CLI shape justifies it. |
| Terminal | Use `golang.org/x/term` for terminal detection and width. | BSD-3-Clause, maintained by the Go project, tagged with current `x/*` releases. |
| Goroutine coordination | Use `golang.org/x/sync/errgroup` only where clearer than `sync.WaitGroup`. | BSD-3-Clause, maintained by the Go project; keep usage narrow because it is not needed for pure package code. |
| Atomic writes | Use `github.com/google/renameio/v2` for history writes. | Apache-2.0, small focused module; use for atomic replace semantics, not durability guarantees. |
| Test diffs | Use `github.com/google/go-cmp` in tests only when useful. | BSD-3-Clause, mature test-only dependency; do not use in production packages. |
| Hashing, JSON, time, process | Use standard library. | Prefer stdlib for stable behavior and smaller binary surface. |
| ANSI rendering | No library; direct escape sequences are simpler. | Avoids unnecessary rendering dependency for one status line. |
| TUI libraries | Do not use Bubble Tea/Lip Gloss. `eta` is one status line, not a TUI. | Avoids transitive UI dependencies and behavior drift. |
| Shell parser | Do not use `mvdan.cc/sh/v3` in MVP; it would change command-key compatibility. | Deferred to a separate migration because parser-aware keys can split existing history. |
| Security scan | Use pinned `golang.org/x/vuln/cmd/govulncheck`. | BSD-3-Clause, Go vulnerability tooling; pin version in CI/tooling once Go module exists. |
| Linting | Evaluate pinned `golangci-lint` as a CI tool only. Keep rules high-signal. | GPL-3.0 tool, not a production dependency; evaluate after parity and pin only if rules add signal. |
| Release | Evaluate GoReleaser after parity for archives, checksums, SBOMs, and attestations. | Tooling-only decision after implementation and dependency audit stabilize. |

Before adding any dependency:

```bash
go list -m -json <module>
go list -m -u -json all
govulncheck ./...
```

## Go Practices

- Prefer concrete types; add interfaces only at consumer boundaries.
- Interfaces belong in the package that consumes them.
- Use `context.Context` for command execution and shutdown, not pure math.
- Use `fmt.Errorf("...: %w", err)` for context.
- Use typed errors for wrapped command exit codes.
- Use `sync.Mutex` only around shared estimator/renderer state.
- Use table-driven tests; add fuzz tests for line normalization and line buffering.
- Use `t.TempDir`, `t.Setenv`, injected clocks, and injected writers in tests.
- Run `go test -race` for process/render/coordinator changes.
- Keep exported comments short and useful.
- Keep stdout/stderr byte-for-byte clean.

## Git History

Commit after meaningful verified batches so the rewrite has reviewable history.

- Commit after each phase or coherent task group, not after every tiny edit.
- Keep commits scoped to one responsibility, such as scaffolding, progress engine, history store, process runner, renderer, coordinator, or cutover.
- Run the relevant acceptance checks before each commit.
- Include task IDs in commit messages when useful, for example `go: implement progress engine (D01-D02)`.
- Do not commit unrelated dirty work.
- Do not squash the whole rewrite into one commit.

## Agent Workflow

The task backlog is designed for a single Codex session first. Subagents are optional.

The Markdown plan does not control Codex's internal task list automatically. A Codex session must read the file, create its own active checklist from the next few task IDs, execute them, and update the file only when a real plan decision changes.

Recommended start prompt:

```text
Use docs/go-rewrite-plan.md as the source of truth. Work through the task backlog in order. Create an active checklist for the next 3-6 unblocked tasks, use subagents only when useful and write scopes do not overlap, complete tasks one by one, run each task's acceptance checks, then update me with results and the next suggested tasks. Keep Swift working until cutover.
```

If subagents are available, use them for useful parallelism when write scopes do not overlap. The lead session picks task IDs from this plan, spawns only safe parallel work, waits for results, and integrates one implementation result at a time.

Roles:

| Agent | Use for | Write scope |
| --- | --- | --- |
| Architecture | Package boundaries, dependency policy, cutover decisions | docs only unless assigned |
| Implementation | One package or one vertical slice | assigned paths only |
| Test runner | Unit/integration/race/performance checks | no writes by default |
| Code review | Bugs, Go idioms, concurrency, missing tests | no writes by default |
| Compatibility | Swift fixture parity and integration parity | fixtures/docs/tests only |
| Dependency audit | Maintenance, license, vulnerabilities, footprint | dependency notes and module files only |
| Documentation | README, AGENTS.md, release docs | docs/support files |

Task card format:

```text
Task ID:
Goal:
Context:
Agent role:
Write scope:
Read scope:
Acceptance checks:
Commands:
Do not:
```

General rules:

- One lead agent owns each phase.
- Single-session execution is valid; do not block waiting for subagents.
- Keep the active checklist small, usually 3-6 tasks, even though the backlog is larger.
- Implementation agents never edit the same package concurrently.
- Implementation tasks with overlapping write scopes are queued, not parallelized.
- Read-only review/test agents may run while one implementation agent is working.
- The lead waits for implementation agents before starting dependent tasks.
- Review/test agents stay read-only unless explicitly assigned a narrow patch.
- Each agent returns a concise summary, changed files, commands run, key failures, assumptions, and remaining risks. Do not paste raw logs unless they are necessary to diagnose a failure.
- Update this plan when real implementation evidence changes a decision.

Start command for Codex:

```text
Start the Go rewrite using docs/go-rewrite-plan.md. Create an active checklist for A00-A03, run A00 first, then continue with the next non-conflicting tasks. Use subagents when useful and safe by write scope. Run acceptance checks and keep Swift working until cutover.
```

## Task Backlog

Each row is small enough for one focused agent task.

| ID | Role | Goal | Write scope | Acceptance |
| --- | --- | --- | --- | --- |
| A00 | Architecture | Re-check this plan against current Swift source/tests | `docs/go-rewrite-plan.md` | mismatches documented or fixed |
| A01 | Dependency audit | Verify MVP deps and tool deps before `go.mod` | dependency section | approved deps have reason/license/maintenance note |
| A02 | Compatibility | Generate Swift golden fixtures | `testdata/swift-compat/` | fixtures cover hashes, normalization, command keys, formatter, sample history |
| A03 | Test runner | Run current Swift baseline | none | commands/results recorded |
| S01 | Implementation | Create Go module and minimal skeleton | `go.mod`, `go.sum` when needed, `cmd/eta/`, `internal/` skeletons | `go test ./...` passes |
| S02 | Implementation | Add Go Makefile targets alongside Swift | `Makefile` | `make go-build`, `make go-test` work |
| S03 | Implementation | Add Go CI job without removing Swift CI | `.github/workflows/ci.yml` | independent Go job passes |
| D01 | Implementation | Hashing and normalization | `internal/hashline/` | Swift fixtures pass |
| D02 | Implementation | Progress types, matcher, timeline, estimator | `internal/progress/` | ported matcher/ETA tests pass |
| D03 | Test runner | Add short fuzz tests for normalization | hashline fuzz tests | fuzz target runs locally |
| H01 | Implementation | History load/save/schema/privacy | `internal/history/` | Swift JSON fixture loads; no raw text stored |
| H02 | Implementation | History pruning/downsampling/clear | `internal/history/` | retention, 5000-line cap, clear tests pass |
| H03 | Implementation | Atomic writes and stale pruning | `internal/history/` | stale files prune; partial-write risk covered where practical |
| K01 | Implementation | Command-key resolution | `internal/commandkey/` | path, bare, and missing executable fixtures match Swift |
| K02 | Compatibility | Reconfirm shell parser remains deferred | plan docs only | command-key migration risk documented |
| P01 | Implementation | Line buffer without `bufio.Scanner` | `internal/process/linebuffer.go` | complete, partial, CR, invalid UTF-8 tests pass |
| P02 | Implementation | Shell runner and stream draining | `internal/process/runner.go` | stdout/stderr/exit/duration tests pass |
| P03 | Implementation | Raw pass-through writer | `internal/process/writer.go` | byte-for-byte output tests pass |
| P04 | Test runner | Stress stdout/stderr under load | none | no deadlock; line counts match |
| R01 | Implementation | Time and progress bar formatter | `internal/render/formatter.go` | ANSI/stripped fixture tests pass |
| R02 | Implementation | Terminal open/width and disabled path | `internal/render/terminal_unix.go` | disabled terminal handled cleanly |
| R03 | Implementation | Renderer redraw locking and first-run header | `internal/render/renderer.go` | redraw/partial-line tests pass |
| R04 | Implementation | Ticker loop | `internal/render/loop.go` | deterministic stop; no goroutine leaks in tests |
| R05 | Implementation | SIGINT/SIGTERM cleanup and re-raise | `internal/render/signals_unix.go` | signal behavior verified by test/integration |
| R06 | Test runner | Pseudo-tty render check | none | progress on tty; redirected stdout/stderr clean |
| C01 | Implementation | CLI parsing and validation | `internal/cli/` | all current valid/invalid cases pass |
| C02 | Implementation | Coordinator workflow with fakes | `internal/coordinator/` | Swift coordinator matrix ported and passing |
| C03 | Implementation | `eta.Main` and tiny `cmd/eta` | `internal/eta/`, `cmd/eta/main.go` | tests call app without process exit; binary exits correctly |
| I01 | Test runner | Go unit, vet, race-sensitive suites | none | results recorded |
| I02 | Test runner | Existing simulate script against Go binary | none | script passes |
| I03 | Test runner | Existing stdio cleanliness script against Go binary | none | no progress leaks or stream mixing |
| I04 | Test runner | Existing large-output script against Go binary | none | runtime under threshold; saved lines exactly 5000 |
| Q01 | Dependency audit | Add `govulncheck`/dependency freshness gate | CI/tool config | no reachable vulnerabilities or unreviewed updates |
| Q02 | Code review | Full pre-cutover review | none | blocking findings fixed |
| X01 | Implementation | Switch Makefile build/install to Go | `Makefile` | `make build/install/clean` target Go binary |
| X02 | Implementation | Switch CI release path to Go | `.github/workflows/ci.yml` | Go release checks required |
| X03 | Documentation | Update README and AGENTS.md | `README.md`, `AGENTS.md` | docs match Go implementation |
| X04 | Documentation | Add release automation plan/config after audit | release docs/config | checksums/provenance path documented |
| X05 | Implementation | Remove Swift implementation after approved cutover | Swift source/package/CI leftovers | one canonical implementation remains |

## Phase Order

1. Freeze parity and fixtures: `A00-A03`.
2. Scaffold Go in parallel with Swift: `S01-S03`.
3. Pure domain logic: `D01-D03`.
4. History and command-key compatibility: `H01-H03`, `K01-K02`.
5. Process runner: `P01-P04`.
6. Rendering, tty, and signals: `R01-R06`.
7. CLI and coordinator: `C01-C03`.
8. Integration and quality gates: `I01-I04`, `Q01-Q02`.
9. Cutover and cleanup: `X01-X05`.

## Verification Gates

Cutover requires all applicable gates:

| Gate | Command |
| --- | --- |
| Format | `test -z "$(gofmt -l $(git ls-files '*.go'))"` |
| Unit | `go test ./...` |
| Race-sensitive | `go test -race ./internal/process ./internal/render ./internal/coordinator` |
| Vet | `go vet ./...` |
| Vulnerability scan | `govulncheck ./...` or `go tool govulncheck ./...` |
| Dependency freshness | `go list -m -u -json all` |
| Simulate | `scripts/ci/test-simulate.sh <go eta binary>` |
| Stdio cleanliness | `scripts/ci/test-stdio-clean.sh <go eta binary>` |
| Large output | `scripts/ci/test-large-output.sh <go eta binary>` |
| Smoke | `<go eta binary> --name codex-smoke --quiet 'printf ok\\n'` |

## Compatibility Risks

- Command-key parsing: keep current first-space behavior first. Shell-aware parsing can split user history and must be a separate migration.
- Unicode normalization: verify Swift `Character.isNumber` parity against Go Unicode behavior with fixtures.
- JSON dates: Go must decode Swift ISO-8601 dates. Byte-for-byte JSON formatting is not required unless tests prove users depend on it.
- Terminal cleanup: explicitly test success, failure, launch error, SIGINT, SIGTERM, partial final line, and redirected stdout/stderr with `/dev/tty`.
- Large output: pipe draining must not block on rendering; avoid `bufio.Scanner` limits.

## Defaults

- Module path: `github.com/Sorix/eta`.
- Go version: target Go 1.26; fall back to Go 1.25 only if CI/package availability requires it.
- MVP production deps: `pflag`, `x/term`, `x/sync`, `renameio`.
- MVP test dep: `go-cmp`.
- Tools to evaluate/pin: `govulncheck`, `golangci-lint`, optional `gofumpt`.
- No Cobra, Kong, TUI framework, color library, config system, plugin system, or shell parser in MVP.
