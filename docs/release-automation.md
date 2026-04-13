# Release Automation Plan

`eta` now builds as a Go binary. Release automation should stay conservative until the first Go release candidate has passed the integration scripts on macOS and Linux.

## Current Config

`.goreleaser.yaml` is intentionally limited to:

- static Go builds from `./cmd/eta`
- `darwin` and `linux`
- `amd64` and `arm64`
- `tar.gz` archives
- `checksums.txt`
- `-trimpath` and commit-timestamped module metadata for more repeatable artifacts

Validate locally with:

```sh
goreleaser check
goreleaser release --snapshot --clean
```

Run the standard gates before tagging:

```sh
make build
make go-test
env GOCACHE=/tmp/eta-go-build go vet ./...
env GOCACHE=/tmp/eta-go-build go test -race ./internal/process ./internal/render ./internal/coordinator ./internal/eta
scripts/ci/test-simulate.sh .build/go/eta
scripts/ci/test-stdio-clean.sh .build/go/eta
scripts/ci/test-large-output.sh .build/go/eta
swift test --parallel
```

## Provenance And Signing

The release workflow should use GitHub Actions OIDC once releases are enabled:

- Generate checksums with GoReleaser.
- Sign `checksums.txt` with keyless Sigstore/cosign.
- Publish the signature and certificate beside the checksums.
- Add artifact attestation after the repository's release workflow exists.

Do not add long-lived signing keys to the repository.

## SBOM

GoReleaser can call Syft to generate SBOMs for release artifacts. Add SBOM generation only after CI installs and pins Syft, then publish SBOM files beside the archives and checksums.

## Deferred

- Homebrew tap or cask
- Linux packages with nfpm
- macOS notarization
- Windows builds
- Container images
