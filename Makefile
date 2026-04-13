SHELL := /bin/bash

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
  DEFAULT_PREFIX := /usr/local
else
  DEFAULT_PREFIX := $(HOME)/.local
endif

PREFIX ?= $(DEFAULT_PREFIX)
GO ?= go
GO_LOCAL := ./scripts/go-local.sh
GO_BUILD_DIR := .build/go
GO_ETA := $(GO_BUILD_DIR)/eta

build: go-build

go-build:
	install -d "$(GO_BUILD_DIR)"
	$(GO_LOCAL) build -o "$(GO_ETA)" ./cmd/eta

go-test:
	$(GO_LOCAL) test ./...

go-vet:
	$(GO_LOCAL) vet ./...

go-race:
	$(GO_LOCAL) test -race ./internal/process ./internal/render ./internal/coordinator ./internal/eta

check:
	test -z "$$(gofmt -l $$(git ls-files '*.go'))"
	$(MAKE) go-test
	$(MAKE) go-vet
	$(MAKE) go-race
	$(MAKE) go-build

ci: check
	go list -m -u -json all
	$(GO_LOCAL) run golang.org/x/vuln/cmd/govulncheck@v1.1.4 ./...
	./scripts/ci/test-simulate.sh "$(GO_ETA)"
	./scripts/ci/test-command-key-resolution.sh "$(GO_ETA)"
	./scripts/ci/test-stdio-clean.sh "$(GO_ETA)"
	./scripts/ci/test-large-output.sh "$(GO_ETA)"

install:
	@if [ "$$(id -u)" -eq 0 ] && [ -n "$$SUDO_USER" ]; then \
		echo "Building eta as $$SUDO_USER"; \
		sudo -u "$$SUDO_USER" -- $(MAKE) build; \
	else \
		$(MAKE) build; \
	fi
	install -d "$(PREFIX)/bin"
	install "$(GO_ETA)" "$(PREFIX)/bin/eta"

uninstall:
	rm -f "$(PREFIX)/bin/eta"

clean:
	rm -rf "$(GO_BUILD_DIR)"

.PHONY: build go-build go-test go-vet go-race check ci install uninstall clean
