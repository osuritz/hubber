# Hubber Agent Guide

## Purpose

Hubber is a macOS menu-bar prototype for keeping GitHub review work visible at a glance. It shows mock data for three work streams:

- Incoming PR reviews assigned to the user, including review SLO status
- Outgoing PRs, including CI state, unresolved comments, and reviewer state
- Draft PRs, including CI state and freshness

The app currently focuses on the Direction A native macOS popover concept. GitHub API integration is not implemented yet.

## Build And Run

Use Xcode 26 / Swift 6 or newer.

```sh
swift build
swift run Hubber
```

`swift run Hubber` starts the menu-bar accessory app and keeps running until the app quits. Left-click the status item to open the popover; right-click it to show the menu with `Quit`.

## Project Layout

- `Package.swift`: Swift Package Manager executable target definition
- `Sources/Hubber/main.swift`: AppKit app delegate, status item, popover, and quit menu wiring
- `Sources/Hubber/HubberPopoverView.swift`: SwiftUI popover UI, tabs, rows, SLO pills, CI badges, and settings view
- `Sources/Hubber/Models.swift`: mock GitHub data and lightweight view models
- `Sources/Hubber/VisualEffectView.swift`: SwiftUI wrapper for `NSVisualEffectView`
- `README.md`: human-facing overview and run instructions

## Current Shape

This is an SPM executable prototype, not a bundled `.app` target yet. Future production work should add a real macOS app target with an `Info.plist`, `LSUIElement`, signing/notarization, app icon, login item support, and real GitHub data plumbing.
