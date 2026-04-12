# Estimation for repeating commands

A progress bar for any command — learns from history, predicts the rest.

```
$ eta 'make build'

==> Configuring project...
==> Resolving dependencies...
[1/8] Compiling utils.c
[2/8] Compiling parser.c
[3/8] Compiling lexer.c
[████████████████████▒▒▒▒▒▒▒▒▒                       ]  44%  ETA 32s
```

## How It Works

`eta` works by remembering what your command printed last time and when each line appeared.

1. **First run** — `eta` hashes every output line and records its timestamp relative to the start. This builds a timeline: which line appeared at what point during execution.
2. **Next run** — as the command runs again, `eta` hashes each new output line and matches it against the stored timeline. When it sees a line that previously appeared at the 30% mark, it knows you're at 30%. Combined with the expected total duration, it calculates a live ETA.
3. **Every run** — the model refines itself, weighting recent runs higher for better predictions.

This approach means `eta` is designed for **commands you run repeatedly** — anything with recognizable, structured output that follows a similar pattern each time.

The progress bar has two layers: **solid fill** for lines already matched against history, and **shaded fill** for timer-based prediction ahead of the last confirmed point. You always know what's verified versus estimated.

```
[██████████████████████▒▒▒▒▒▒▒▒▒▒           ]  64%  ETA 18s
 ▲ confirmed from output ▲ predicted         ▲ remaining
```

## Use Cases

`eta` works best with commands that produce output and are run regularly:

- **Build systems** — `make`, `cmake`, `swift build`, `cargo build`, `go build`, `gradle assemble`, `npm run build`, `webpack`
- **Test suites** — `pytest`, `swift test`, `cargo test`, `jest`, `go test ./...`
- **CI/CD scripts** — deployment pipelines, release scripts, environment provisioning
- **Infrastructure** — `terraform apply`, `ansible-playbook`, `docker build`
- **Data pipelines** — database migrations, ETL jobs, batch processing scripts
- **Package management** — `pod install`, `npm install`, `bundle install`

`eta` is **not useful** for commands with no output or unpredictable one-off output (e.g. `cp`, `mv`, `curl`). It needs repeating structured output to learn from.

## Features

**Pipe-safe** — the progress bar renders on `/dev/tty`, completely separate from stdout/stderr. Your command's output stays clean for piping, redirecting, or logging. Nothing changes for downstream tools.

**Privacy-first storage** — `eta` keeps only cryptographic hashes: SHA-256 for command keys, MD5 for output lines. History files cannot be reversed into original content.

**Smart line matching** — each output line is matched against history using an exact hash first, then a normalized fallback that collapses numbers and whitespace. Lines like `[3/100] Compiling foo.swift` match across runs even when counts or paths change.

**Adaptive estimates** — ETA uses an exponential weighted mean (alpha=0.3) so recent runs matter more than old ones. If your build gets faster or slower over time, `eta` adjusts.

**Self-maintaining history** — stale history files are automatically pruned after 90 days. Each run is downsampled to 5,000 lines max. Old runs are rotated out (default: keep last 10).

## Install
Software is in alpha-test, releases will be published later.

### User install

```sh
git clone https://github.com/Sorix/eta
cd eta
make install
```

### Installation

```sh
make install # sudo required for macOS
make uninstall # to uninstall
```

## Usage

```sh
# Basic — wrap any command
eta 'swift build 2>&1 | xcbeautify --is-ci'

# Name a command for stable history across argument changes
eta --name deploy './deploy.sh --env staging --region us-east-1'

# Choose a bar color
eta --color cyan 'cargo build --release'

# Solid fill style (no confirmed/predicted distinction)
eta --solid 'npm run build'

# Learn timing without showing a bar (headless / CI)
eta --quiet 'make test'

# Use more history for averaging
eta --runs 20 'gradle assemble'
```

### History management

```sh
# Clear history for one command
eta --clear 'make build'

# Clear all history
eta --clear-all
```

### Where history lives

| Platform | Path |
|----------|------|
| macOS | `~/Library/Caches/eta/` |
| Linux | `$XDG_CACHE_HOME/eta/` or `~/.cache/eta/` |

Each command gets one JSON file, named by its SHA-256 hash.
