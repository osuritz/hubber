# Contributing to Hubber

Thanks for helping. This page covers the practical parts: reporting bugs, building the project, what a good PR looks like, and the license agreement every contribution needs.

## Reporting a bug

Open a GitHub issue with what you did, what you expected, and what happened, plus your macOS and Hubber versions.

For a crash, attach the `crash-<date>.log` from `~/Library/Logs/Hubber/`. Read it first and remove anything private: it contains the error message, a backtrace, and recent log lines, and can include GitHub logins.

## Development setup

You need Xcode 26 (Swift 6 or newer). After cloning, run once:

```sh
make setup        # enables the pre-push hook and the blame ignore list
```

Common commands:

```sh
swift build           # or: make build
swift run Hubber      # start the menu-bar app
make test             # run the test target
make lint             # SwiftLint check
make format-lint      # SwiftFormat check (fails on drift, rewrites nothing)
make format           # reformat Sources/ and Tests/ in place
make fix              # autocorrect SwiftLint violations, then reformat
make ci               # build + test + lint + format-lint, exactly what CI runs
```

The lint tools are pinned and installed into `.build/lint-tools` on first use. See [AGENTS.md](AGENTS.md) for the project layout and more detail.

## Pull requests

- Keep PRs small and focused on one change.
- Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`).
- Run `make ci` and make sure it passes before you push. `swift build` alone does not compile the tests.
- Add or update tests for any change in behaviour.
- If an issue exists, put `Closes #NN` in the PR description so it closes on merge.

## Licensing and the CLA

Hubber is dual-licensed: GPL-3.0 for everyone (see [LICENSE](LICENSE)), and a commercial license offered by the project owner (see [COMMERCIAL.md](COMMERCIAL.md)). To keep offering the commercial license, the owner needs permission to relicense every contribution, which GPL-3.0 alone does not give.

So before a PR can be merged, read the [Contributor License Agreement](CLA.md) and confirm you agree by ticking the checkbox in the PR template. You keep ownership of your contribution; the CLA is a license grant, not a copyright assignment. PRs without that confirmation cannot be merged.

## Privacy

Hubber's telemetry is opt-in and must never carry user data: no logins, repository names, PR titles, or tokens. See [PRIVACY.md](PRIVACY.md) for exactly what is sent. Any change to telemetry needs a matching update to PRIVACY.md in the same PR.
