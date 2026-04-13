SHELL := /bin/bash

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
  DEFAULT_PREFIX := /usr/local
else
  DEFAULT_PREFIX := $(HOME)/.local
endif

PREFIX ?= $(DEFAULT_PREFIX)
GO ?= go
GO_BUILD_DIR := .build/go
GO_CACHE_DIR := $(CURDIR)/$(GO_BUILD_DIR)/cache
GO_ETA := $(GO_BUILD_DIR)/eta

build: go-build

go-build:
	install -d "$(GO_BUILD_DIR)"
	GOCACHE="$(GO_CACHE_DIR)" $(GO) build -o "$(GO_ETA)" ./cmd/eta

go-test:
	GOCACHE="$(GO_CACHE_DIR)" $(GO) test ./...

install: build
	install -d "$(PREFIX)/bin"
	install "$(GO_ETA)" "$(PREFIX)/bin/eta"

uninstall:
	rm -f "$(PREFIX)/bin/eta"

clean:
	rm -rf "$(GO_BUILD_DIR)"

.PHONY: build go-build go-test install uninstall clean
