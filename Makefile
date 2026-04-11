PREFIX ?= /usr/local

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/eta $(PREFIX)/bin/eta

uninstall:
	rm -f $(PREFIX)/bin/eta

clean:
	swift package clean

.PHONY: build install uninstall clean
