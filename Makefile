SHELL := /bin/bash

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
  DEFAULT_PREFIX := /usr/local
else
  DEFAULT_PREFIX := $(HOME)/.local
endif

PREFIX ?= $(DEFAULT_PREFIX)

build:
	swift build -c release

install: build
	install -d "$(PREFIX)/bin"
	install .build/release/eta "$(PREFIX)/bin/eta"

uninstall:
	rm -f "$(PREFIX)/bin/eta"

clean:
	swift package clean

.PHONY: build install uninstall clean
