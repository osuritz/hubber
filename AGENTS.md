# Hubber Agent Guide

## Purpose

Hubber is a macOS menu-bar prototype for keeping GitHub review work visible at a glance. It shows mock data for three work streams:

- Incoming PR reviews assigned to the user, including review SLO status
- Outgoing PRs, including CI state, unresolved comments, and reviewer state
- Draft PRs, including CI state and freshness

The app currently focuses on the Direction A native macOS popover concept. GitHub API integration is not implemented yet.

## Commits

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Prefix commit messages with a type:

- `feat:` — new feature
- `fix:` — bug fix
- `refactor:` — code change that is neither a fix nor a feature
- `chore:` — tooling, config, dependencies
- `docs:` — documentation only

## Linting and Formatting

This project uses [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), pinned to the versions in `Scripts/lint-tools.env` (see "Pinned lint tools" below). Install the pinned versions locally:

```sh
bash Scripts/install-lint-tools.sh .build/lint-tools
export PATH="$PWD/.build/lint-tools:$PATH"
```

Run via the Makefile:

```sh
make lint    # check for SwiftLint violations
make format  # reformat source files in place (SwiftFormat — rewrites files)
make fix     # autocorrect SwiftLint violations, then reformat
```

Note that `make lint` covers SwiftLint only. CI additionally runs
`swiftformat --lint` (check mode, fails on drift), which is *not* the same as
`make format` (which silently rewrites files). Use `make ci` (below) to catch
formatting drift the way CI does.

### Pinned lint tools

CI installs SwiftFormat and SwiftLint from `Scripts/lint-tools.env` (version and
sha256 of the GitHub release asset) via `Scripts/install-lint-tools.sh`, with no
Homebrew, so a new tool release can't break the build. `make lint` and `make ci`
(and so the pre-push hook) warn if your local versions differ. To bump a tool:

1. Edit `Scripts/lint-tools.env` (version and sha256; GitHub shows the digest on each release asset).
2. Run the new `swiftformat` on `Sources/ Tests/` and commit the reformat in the same PR.
3. CI verifies.

Rules are configured in `.swiftlint.yml` and `.swiftformat`. Key constraints: 120-character line limit, Swift 6.0, Google Swift Style Guide conventions (no force unwraps/casts/tries, sorted imports, trailing commas in multi-line collections).

## Build And Run

Use Xcode 26 / Swift 6 or newer.

```sh
swift build
swift run Hubber
```

`swift run Hubber` starts the menu-bar accessory app and keeps running until the app quits. Left-click the status item to open the popover; right-click it to show the menu with `Quit`.

## Validating Before You Push

CI (`.github/workflows/swift.yml`) runs automatically on push to `main` and on
PRs while the repo variable `MACOS_RUNS_ON` routes it to the self-hosted Mac mini;
with the variable unset it is manual-only on hosted `macos-26` to cut runner spend.
Either way, validate locally first — and a plain `swift build`
is not enough. `swift build` does *not* compile the test target, so test-target
compile errors (e.g. Swift 6.2 actor-isolation) and test failures slip through.

Run the full CI-parity gate before pushing:

```sh
make ci      # build + swift test + swiftlint + swiftformat --lint
make test    # just the test target, on its own
```

`make ci` runs exactly what CI runs, in the same modes. If `make ci` is green,
CI will be green.

### Pre-push hook

A tracked Git hook (`.githooks/pre-push`) runs `make ci` automatically on every
push. Hooks live in `.githooks/` (version-controlled), so after a fresh clone
enable them once with:

```sh
git config core.hooksPath .githooks
```

Bypass the hook for an emergency push with `git push --no-verify`, or skip just
this check with `SKIP_CI_HOOK=1 git push`.

## Project Layout

- `Package.swift`: Swift Package Manager executable target definition
- `Sources/Hubber/main.swift`: AppKit app delegate, status item, popover, and quit menu wiring
- `Sources/Hubber/HubberPopoverView.swift`: SwiftUI popover UI, tabs, rows, SLO pills, CI badges, and settings view
- `Sources/Hubber/Models.swift`: mock GitHub data and lightweight view models
- `Sources/Hubber/VisualEffectView.swift`: SwiftUI wrapper for `NSVisualEffectView`
- `README.md`: human-facing overview and run instructions

## Current Shape

This is an SPM executable prototype, not a bundled `.app` target yet. Future production work should add a real macOS app target with an `Info.plist`, `LSUIElement`, signing/notarization, app icon, login item support, and real GitHub data plumbing.
