.PHONY: lint format fix build app zip dmg dist pkg

SWIFT_PATHS = Sources/ Tests/

build:
	swift build

lint:
	swiftlint lint --no-cache $(SWIFT_PATHS)

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
