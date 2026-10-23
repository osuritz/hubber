.PHONY: lint lint-tools-check format fix build test ci app app-dev zip dmg dist pkg

SWIFT_PATHS = Sources/ Tests/

# Pinned SwiftFormat/SwiftLint versions (shared with CI); sets SWIFTFORMAT_VERSION
# and SWIFTLINT_VERSION.
include Scripts/lint-tools.env

build:
	swift build

test:
	swift test

## Warn (never fail) when the local lint tools differ from the versions pinned in
## Scripts/lint-tools.env, since CI uses the pinned ones.
lint-tools-check:
	@fix='bash Scripts/install-lint-tools.sh .build/lint-tools && export PATH="$$PWD/.build/lint-tools:$$PATH"'; \
	v=$$(swiftformat --version 2>/dev/null); \
	[ "$$v" = "$(SWIFTFORMAT_VERSION)" ] || echo "warning: swiftformat $${v:-not found}, CI pins $(SWIFTFORMAT_VERSION). Fix: $$fix" >&2; \
	v=$$(swiftlint version 2>/dev/null); \
	[ "$$v" = "$(SWIFTLINT_VERSION)" ] || echo "warning: swiftlint $${v:-not found}, CI pins $(SWIFTLINT_VERSION). Fix: $$fix" >&2; \
	true

lint: lint-tools-check
	swiftlint lint --no-cache $(SWIFT_PATHS)

## Mirror exactly what CI (.github/workflows/swift.yml) runs. Use this as the
## pre-push gate so "passes locally" means the same thing as "passes in CI".
## Note: `swift test` compiles the test target (plain `swift build` does not),
## and `swiftformat --lint` only checks — it does NOT rewrite files like
## `make format` does.
ci: build test lint
	swiftformat --lint $(SWIFT_PATHS)

format:
	swiftformat $(SWIFT_PATHS)

fix:
	swiftlint lint --fix --no-cache $(SWIFT_PATHS)
	swiftformat $(SWIFT_PATHS)

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
