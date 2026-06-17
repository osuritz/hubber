.PHONY: lint format fix build test ci app zip dmg dist pkg

SWIFT_PATHS = Sources/ Tests/

build:
	swift build

test:
	swift test

lint:
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
