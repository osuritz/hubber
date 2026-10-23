.PHONY: lint-tools lint format-lint format fix build test ci app app-dev zip dmg dist pkg

SWIFT_PATHS = Sources/ Tests/

# The lint tools always come from the pinned install, never from PATH, so local
# runs and CI can't disagree. Override a binary deliberately if you must, e.g.
# `make lint SWIFTLINT=$(which swiftlint)`.
LINT_TOOLS_DIR = .build/lint-tools
SWIFTFORMAT ?= $(LINT_TOOLS_DIR)/swiftformat
SWIFTLINT ?= $(LINT_TOOLS_DIR)/swiftlint

# Pinned SwiftFormat/SwiftLint versions (shared with CI); sets SWIFTFORMAT_VERSION
# and SWIFTLINT_VERSION.
include Scripts/lint-tools.env

build:
	swift build

test:
	swift test

## Install the pinned SwiftFormat/SwiftLint into .build/lint-tools (gitignored).
## Idempotent: a stamp per tool makes repeat runs cheap and offline.
lint-tools:
	bash Scripts/install-lint-tools.sh $(LINT_TOOLS_DIR)

lint: lint-tools
	$(SWIFTLINT) lint --no-cache $(SWIFT_PATHS)

## Check-only SwiftFormat run (fails on drift, never rewrites files).
format-lint: lint-tools
	$(SWIFTFORMAT) --lint $(SWIFT_PATHS)

## Mirror exactly what CI (.github/workflows/swift.yml) runs. Use this as the
## pre-push gate so "passes locally" means the same thing as "passes in CI".
## Note: `swift test` compiles the test target (plain `swift build` does not),
## and `format-lint` only checks — it does NOT rewrite files like `make format`
## does.
ci: build test lint format-lint

format: lint-tools
	$(SWIFTFORMAT) $(SWIFT_PATHS)

fix: lint-tools
	$(SWIFTLINT) lint --fix --no-cache $(SWIFT_PATHS)
	$(SWIFTFORMAT) $(SWIFT_PATHS)

# ---------------------------------------------------------------------------
# Distribution targets
# ---------------------------------------------------------------------------

## Build a universal, ad-hoc-signed Hubber.app in the project root.
app:
	bash Scripts/make-app.sh $(VERSION)

## Build a local DEBUG Hubber.app for development. Compiled with `#if DEBUG`, so
## it uses the file token store (not the Keychain) and won't re-prompt for
## Keychain access after every ad-hoc-signed rebuild. Use this for local testing;
## `make app` stays the release/distribution build.
app-dev:
	HUBBER_BUILD_CONFIG=debug bash Scripts/make-app.sh $(VERSION)

## Package Hubber.app into dist/Hubber.zip (preserves code signature via ditto).
zip: app
	mkdir -p dist
	ditto -c -k --keepParent Hubber.app dist/Hubber.zip
	@echo "==> dist/Hubber.zip"

## Build a distributable DMG containing Hubber.app + /Applications symlink.
dmg: app
	bash Scripts/make-dmg.sh Hubber.app dist/Hubber.dmg

## Build all distribution artifacts (DMG + zip).
dist: app dmg zip

## Build an MDM-compatible .pkg installer that installs Hubber.app to /Applications.
## Set HUBBER_INSTALLER_SIGN_IDENTITY for a signed pkg (required for silent MDM deploy).
pkg: app
	bash Scripts/make-pkg.sh $(VERSION)
