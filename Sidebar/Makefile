.PHONY: build test demo install uninstall snapshot app

build:
	swift build

test:
	swift test

# Scripted fake session: every animation, no tokens spent.
demo: build
	.build/debug/agentworld-sidebar --demo

# One frame of the current project's session, printed to stdout.
snapshot: build
	.build/debug/agentworld-sidebar --once --size 56x60

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

# The macOS app, built, bundled and installed to ~/Applications.
app:
	./scripts/build-app.sh
