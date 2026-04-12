SHELL := /bin/bash

PREFIX ?= $(HOME)/.local
SUDO ?=

build:
	swift build -c release

install: build
	$(SUDO) install -d "$(PREFIX)/bin"
	$(SUDO) install .build/release/eta "$(PREFIX)/bin/eta"

uninstall:
	$(SUDO) rm -f "$(PREFIX)/bin/eta"

clean:
	swift package clean

.PHONY: build install uninstall clean
