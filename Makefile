PREFIX ?= /usr/local

.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	sh scripts/bundle.sh

run: app
	open build/Spaced.app

# Copies the app to /Applications and puts the `spaced` command on the PATH.
install: app
	rm -rf /Applications/Spaced.app
	cp -R build/Spaced.app /Applications/Spaced.app
	mkdir -p $(PREFIX)/bin
	ln -sf /Applications/Spaced.app/Contents/Helpers/spaced $(PREFIX)/bin/spaced

clean:
	swift package clean
	rm -rf build
