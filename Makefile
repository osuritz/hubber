.PHONY: lint format fix build

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
