.PHONY: lint format fix build

build:
	swift build

lint:
	swiftlint lint --no-cache Sources/

format:
	swiftformat Sources/

fix:
	swiftlint lint --fix --no-cache Sources/
	swiftformat Sources/
