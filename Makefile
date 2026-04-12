SHELL := /bin/bash

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
  ifeq ($(UNAME_M),arm64)
    DEFAULT_PREFIX := /opt/homebrew
  else
    DEFAULT_PREFIX := /usr/local
  endif
else
  DEFAULT_PREFIX := $(HOME)/.local
endif

PREFIX ?= $(DEFAULT_PREFIX)
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
