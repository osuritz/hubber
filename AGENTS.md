# Hubber Agent Guide

## Purpose

Hubber is a macOS menu-bar app that keeps code-review work visible at a glance. It shows live data for three work streams:

- Incoming PR reviews assigned to the user, including review SLO status
- Outgoing PRs, including CI state, unresolved comments, and reviewer state
- Draft PRs, including CI state and freshness

Supported hosts are github.com, GitHub Enterprise Server, and GitLab, with multiple accounts at once. See `PRODUCT.md` for the product statement and decision rules, and `PRIVACY.md` for what data is handled.

## Commits

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Prefix commit messages with a type:

- `feat:` — new feature
- `fix:` — bug fix
- `refactor:` — code change that is neither a fix nor a feature
- `chore:` — tooling, config, dependencies
- `docs:` — documentation only

## Linting and Formatting

This project uses [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), pinned to the versions in `Scripts/lint-tools.env` (see "Pinned lint tools" below). The make targets below install the pinned versions into `.build/lint-tools` on first use and always run those binaries, never whatever is on your `PATH` or in Homebrew, so local results match CI. You can also run `make lint-tools` to install them on their own.

Run via the Makefile:

```sh
make lint         # check for SwiftLint violations
make format-lint  # check SwiftFormat drift (check-only, as CI does)
make format       # reformat source files in place (SwiftFormat — rewrites files)
make fix          # autocorrect SwiftLint violations, then reformat
```

Note that `make lint` covers SwiftLint only. CI additionally runs
`make format-lint` (SwiftFormat check mode, fails on drift), which is *not* the
same as `make format` (which silently rewrites files). Use `make ci` (below) to
catch formatting drift the way CI does.

### Pinned lint tools

CI and the make targets install SwiftFormat and SwiftLint from
`Scripts/lint-tools.env` (version and sha256 of the GitHub release asset) via
`Scripts/install-lint-tools.sh`, with no Homebrew, so a new tool release can't
break the build. The install is idempotent (a stamp file per tool), so repeat
runs are cheap and work offline. To run a
different binary on purpose, override the variables, e.g.
`make lint SWIFTLINT=$(which swiftlint)`. To bump a tool:

1. Edit `Scripts/lint-tools.env` (version and sha256; GitHub shows the digest on each release asset).
2. Run the new `swiftformat` on `Sources/ Tests/` and commit the reformat in the same PR.
3. CI verifies.

`.git-blame-ignore-revs` lists the squash SHAs of formatting-only commits (such as tool bumps) so blame skips them. For local `git blame`, run `make setup` once per clone; it sets `blame.ignoreRevsFile` for you.

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
make ci      # build + swift test + swiftlint + swiftformat --lint (pinned tools)
make test    # just the test target, on its own
```

`make ci` runs exactly what CI runs, in the same modes. If `make ci` is green,
CI will be green.

### Pre-push hook

A tracked Git hook (`.githooks/pre-push`) runs `make ci` automatically on every
push. Hooks live in `.githooks/` (version-controlled), so after a fresh clone
run `make setup` once. It enables the pre-push hook and the blame ignore list:

```sh
make setup
```

Bypass the hook for an emergency push with `git push --no-verify`, or skip just
this check with `SKIP_CI_HOOK=1 git push`.

## Project Layout

- `Package.swift`: SPM manifest (macOS 14+, Swift 6; depends on Sparkle and TelemetryDeck)
- `Sources/Hubber/`: the app. `main.swift` is the AppKit entry point (status item, panel, menu); the popover, rows, and settings SwiftUI views sit at the top level. Subdirectories:
  - `Core/`: provider-neutral domain: `CodeHostProvider`, connections and registry, refresh scheduling, `SettingsStore`, managed (MDM) preferences, token storage
  - `GitHub/`, `GitLab/`: provider implementations and auth
  - `Notifications/`: change detection, batching, and delivery of user notifications
  - `AddAccount/`, `Account/`, `Settings/`, `Onboarding/`: account management and first-run UI
  - `Diagnostics/`, `Telemetry/`: crash capture and logging; opt-in analytics
  - `Updates/`: Sparkle updater wiring
  - `Accessibility/`, `Design/`, `Resources/`: accessibility helpers, design tokens and controls, bundled assets
  - `Debug/`: mock providers, compiled only in DEBUG builds
- `Tests/HubberTests/`: test target
- `Scripts/`: `make-app.sh` (assembles the `.app`), `make-dmg.sh`, `make-pkg.sh`, lint-tool installer
- `docs/`: design notes, enterprise/MDM guides, runbooks, `token-permissions.md`
- `.github/workflows/`: CI and the tag-triggered release workflow
- `README.md`: human-facing overview and install instructions
- `PRODUCT.md`, `PRIVACY.md`: product statement and privacy notice

## Current Shape

Hubber is built as an SPM executable and packaged into a bundled `.app` by `make app` (`Scripts/make-app.sh`): a universal binary with an `Info.plist` (`LSUIElement`), embedded Sparkle framework, inside-out ad-hoc code signing (override with `HUBBER_SIGN_IDENTITY`). `make app-dev` builds a DEBUG `.app` that uses the file token store instead of the Keychain. `make dist` adds `dist/Hubber.dmg` and `dist/Hubber.zip`; `make pkg` builds an MDM-oriented installer. Pushing a `v*` tag runs `.github/workflows/release.yml`, which signs with the `Hubber Self-Signed` certificate, runs `make dist`, creates a GitHub release, and publishes the Sparkle appcast to `docs/appcast.xml` on `main` (served by GitHub Pages). See `docs/runbooks/sparkle-auto-update.md`.

Not done: notarization. Sparkle only activates when `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` are set at build time; the release workflow sets them from repository variables, local builds do not.
