# Hubber

Hubber is a macOS menu-bar prototype for keeping GitHub review work visible at a glance.

It is currently mock-data only. The app is focused on validating a native macOS popover experience for three GitHub work streams: incoming reviews, outgoing pull requests, and draft pull requests.

## Status

Prototype. Hubber runs as a Swift Package Manager executable and is not packaged as a signed `.app` bundle yet.

## Features

- Menu-bar status item with an unread-style review count
- Native AppKit `NSStatusItem` and `NSPopover` shell
- SwiftUI popover UI with three tabs: `Incoming`, `Outgoing`, and `Drafts`
- Count badges beside each tab label
- GitHub App Device Flow sign-in from settings
- Keychain storage for GitHub user access and refresh tokens
- Incoming review rows with review SLO status pills
- Outgoing PR rows with CI status, unresolved comments, and reviewer state
- Draft PR rows with CI status and freshness
- Settings view for review SLO display and row density
- Right-click status item menu with `Quit`

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
- Choose `Quit` from the right-click menu to stop the app.
- Use the gear button in the popover to adjust mock SLO display and row density settings.

## Project Layout

```text
Package.swift
Sources/
  Hubber/
    main.swift
    GitHubAuth.swift
    GitHubAppConfig.swift
    HubberPopoverView.swift
    Models.swift
    VisualEffectView.swift
```

- `Package.swift`: Swift Package Manager executable target definition
- `Sources/Hubber/main.swift`: AppKit app delegate, menu-bar status item, popover, and quit menu wiring
- `Sources/Hubber/GitHubAuth.swift`: GitHub App Device Flow client, token refresh, Keychain token storage, and auth view state
- `Sources/Hubber/GitHubAppConfig.swift`: non-secret GitHub App metadata used by the future Device Flow integration
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

GitHub App Device Flow sign-in is implemented. The current pull request data is still static mock data in `Sources/Hubber/Models.swift`.

The GitHub App numeric ID and Client ID are configured in `Sources/Hubber/GitHubAppConfig.swift`. Do not store a client secret in this desktop app.

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

- Replace mock data with GitHub API data
- Package Hubber as a real `.app`
- Add app icon and release metadata
- Persist settings
- Add keyboard shortcuts that match the footer hints
- Derive the menu-bar badge from live review counts
