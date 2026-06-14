# Hubber

Hubber is a first-pass macOS menu-bar app for keeping GitHub review work visible at a glance.

This version is intentionally mock-data only. It implements the Direction A concept from the prototype:

- Three main tabs: Incoming, Outgoing, and Drafts
- Count badges beside each tab label
- Incoming PR reviews with SLO status pills
- Outgoing PRs with CI state, unresolved comments, and reviewer state
- Draft PRs with CI state and freshness
- A compact settings panel for review SLO display and row density

## Run

Open the package in Xcode or run it from Terminal:

```sh
swift run Hubber
```

The app runs as a menu-bar accessory. Click the Hubber status item to open the popover.
