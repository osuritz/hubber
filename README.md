# Hubber

Hubber is a macOS menu-bar prototype for keeping GitHub review work visible at a glance.

It is currently a prototype with mock incoming/outgoing data and a live draft PR proof of concept. The app is focused on validating a native macOS popover experience for three GitHub work streams: incoming reviews, outgoing pull requests, and draft pull requests.

## Install

### Download (DMG or zip)

1. Go to the [latest release](https://github.com/osuritz/hubber/releases/latest) and download `Hubber.dmg` or `Hubber.zip`.
2. Open the DMG and drag **Hubber** to your **Applications** folder (or unzip and move `Hubber.app` to `/Applications`).
3. **First launch: right-click → Open** (or go to **System Settings → Privacy & Security → "Open Anyway"**).
   Hubber is ad-hoc-signed but not notarized, so macOS Gatekeeper will warn on the first browser-downloaded launch.
4. When Hubber asks for notification permission, click **Allow** so review banners can appear.

### One-liner installer (no Gatekeeper warning)

```sh
curl -fsSL https://raw.githubusercontent.com/osuritz/hubber/main/install.sh | bash
```

The installer downloads the release zip via `curl` (which bypasses Gatekeeper quarantine), strips the quarantine attribute, installs to `/Applications`, and opens the app automatically.

> **Note:** Hubber is ad-hoc-signed, not notarized. Notarization (for a fully seamless download experience) requires a paid Apple Developer account and is planned for a future milestone.

---

## Status

Prototype. Hubber runs as a Swift Package Manager executable and is not packaged as a signed `.app` bundle yet.

## Features

- Menu-bar status item with an unread-style review count
- Native AppKit `NSStatusItem` and `NSPopover` shell
- SwiftUI popover UI with three tabs: `Incoming`, `Outgoing`, and `Drafts`
- Count badges beside each tab label
- GitHub App Device Flow sign-in from settings
- Debug token storage in an app-local file, with Keychain storage reserved for release builds
- Live draft PR refresh on sign-in, every 5 minutes, and from the header refresh button
- Incoming review rows with review SLO status pills
- Outgoing PR rows with CI status, unresolved comments, and reviewer state
- Draft PR rows with CI status and freshness
- Settings view for review SLO display and row density
- Developer panel with recent auth and refresh logs
- Right-click status item menu with `Sign Out` and `Quit`

## Requirements

- macOS
- Xcode 26 or newer
- Swift 6 or newer

## Build

```sh
swift build
```

## Run

```sh
swift run Hubber
```

`swift run Hubber` starts the menu-bar accessory app and keeps the Terminal command running until Hubber quits.

## Using The Prototype

- Left-click the Hubber menu-bar item to open or close the popover.
- Right-click the Hubber menu-bar item to open the app menu.
- Choose `Sign Out` from the right-click menu to clear the saved GitHub token.
- Choose `Quit` from the right-click menu to stop the app.
- Use the gear button in the popover to adjust mock SLO display and row density settings.
- Use the refresh button beside the gear to fetch draft PRs immediately after signing in.

## Project Layout

```text
Package.swift
Sources/
  Hubber/
    main.swift
    GitHubAuth.swift
    GitHubAppConfig.swift
    GitHubPullRequestService.swift
    HubberPopoverView.swift
    Models.swift
    VisualEffectView.swift
```

- `Package.swift`: Swift Package Manager executable target definition
- `Sources/Hubber/main.swift`: AppKit app delegate, menu-bar status item, popover, and quit menu wiring
- `Sources/Hubber/GitHubAuth.swift`: GitHub App Device Flow client, token refresh, development token storage, release Keychain token storage, and auth view state
- `Sources/Hubber/GitHubAppConfig.swift`: non-secret GitHub App metadata used by the Device Flow integration
- `Sources/Hubber/GitHubPullRequestService.swift`: GitHub GraphQL client for draft pull request data
- `Sources/Hubber/HubberPopoverView.swift`: SwiftUI popover UI, tabs, rows, settings, SLO pills, CI badges, and avatar views
- `Sources/Hubber/Models.swift`: mock GitHub data and lightweight data models
- `Sources/Hubber/VisualEffectView.swift`: SwiftUI wrapper around `NSVisualEffectView`
- `AGENTS.md`: short guide for coding agents working in this repository

## macOS App Notes

Hubber deliberately starts as a small SPM executable so the product shape can move quickly. Before it is treated as a distributable macOS app, the project should grow into a bundled app target with:

- `Info.plist` app metadata
- `LSUIElement` menu-bar-only behavior
- App icon and asset catalog
- Code signing and notarization
- Release/archive workflow
- Login item support, if the app should launch at startup

## GitHub Integration

GitHub App Device Flow sign-in is implemented. After sign-in, Hubber fetches the viewer's open draft PRs with GitHub GraphQL immediately, then every 5 minutes. Incoming reviews and outgoing PRs still use static mock data in `Sources/Hubber/Models.swift`.

The draft PR query only sees repositories that the Hubber GitHub App token can access. If a repository is visible in the browser but missing in Hubber, install or authorize the GitHub App for that repository/account and sign in again.

The GitHub App Client ID is configured in `Sources/Hubber/GitHubAppConfig.swift`. Do not store a client secret in this desktop app.

Debug builds store the GitHub token in `~/Library/Application Support/Hubber/github-auth-dev.json` to avoid repeated Keychain prompts while iterating on the unsigned SwiftPM executable. Release builds use Keychain storage instead.

Expected future data sources include:

- Pull requests where the user is requested as a reviewer
- Pull requests authored by the user
- Draft pull requests authored by the user
- CI/check-run status
- Outstanding review comments or unresolved review threads
- Review SLO timestamps

## Troubleshooting

If `swift run Hubber` appears to hang, that is expected: the process is running the menu-bar app event loop. Quit Hubber from the right-click menu or stop the process from Terminal.

If the status item is hard to find, look on the right side of the macOS menu bar for the Hubber symbol and count.

## Roadmap

- Replace remaining mock data with GitHub API data
- Package Hubber as a real `.app`
- Add app icon and release metadata
- Persist settings
- Add keyboard shortcuts that match the footer hints
- Derive the menu-bar badge from live review counts

## License

Hubber is **dual-licensed**:

- **GPL-3.0** (open source) — see [`LICENSE`](LICENSE). Use, modify, and redistribute
  Hubber under the GNU General Public License v3.0; any version you distribute must also
  be GPL-3.0 with its source.
- **Commercial license** — for use without the copyleft obligations (e.g. shipping a
  closed-source derivative or embedding Hubber in a proprietary product) and for
  enterprise support. See [`COMMERCIAL.md`](COMMERCIAL.md).

Using Hubber as-is — including inside a company — is free under GPL-3.0; a commercial
license is only needed to distribute a proprietary derivative or to obtain commercial
support.

Copyright © 2026 Olivier Suritz.
