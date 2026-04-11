SHELL := /bin/bash

PREFIX ?= /usr/local

build:
	set -o pipefail; swift build -c release 2>&1 | xcbeautify --is-ci

install: build
	install -d $(PREFIX)/bin
	install .build/release/eta $(PREFIX)/bin/eta

uninstall:
	rm -f $(PREFIX)/bin/eta

clean:
	swift package clean

.PHONY: build install uninstall clean
