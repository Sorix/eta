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
GO_ETA := $(GO_BUILD_DIR)/eta

build:
	swift build -c release

go-build:
	install -d "$(GO_BUILD_DIR)"
	$(GO) build -o "$(GO_ETA)" ./cmd/eta

go-test:
	$(GO) test ./...

install: build
	install -d "$(PREFIX)/bin"
	install .build/release/eta "$(PREFIX)/bin/eta"

uninstall:
	rm -f "$(PREFIX)/bin/eta"

clean:
	swift package clean

.PHONY: build go-build go-test install uninstall clean
