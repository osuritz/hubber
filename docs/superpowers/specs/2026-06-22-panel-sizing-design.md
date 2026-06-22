# Panel sizing: manual width + screen-adaptive height

**Date:** 2026-06-22
**Status:** Approved (pending implementation plan)

## Problem

The menu-bar panel is a fixed 420 × 540 pt (`Sources/Hubber/main.swift:9`,
`private static let panelSize = NSSize(width: 420, height: 540)`). Two issues:

1. **Width feels narrow** for the PR rows — repo + PR title + the secondary line
   (size indicator) get truncated more than they should.
2. **Height is fixed** regardless of display. On a large external monitor there is
   plenty of vertical space, but the panel still shows the same handful of rows it
   does on a laptop.

## Goals

- Make the panel **width** user-adjustable, with a live preview so the user can drag
  and settle on a value.
- Make the panel **height** automatically use more of the available screen so larger
  displays show more PRs at once, with zero configuration.

## Non-goals (YAGNI)

- Adjustable or persisted height.
- Size-to-content height (shrink to the number of PRs).
- Per-screen / per-display remembered widths.
- Drag-to-resize the panel edge.

---

## Design

### 1. Width — user setting with live preview

**`SettingsStore` (`Sources/Hubber/Core/SettingsStore.swift`)**

- New published property, following the established pattern:

  ```swift
  @Published var panelWidth: Double {
      didSet { defaults.set(panelWidth, forKey: "panelWidth") }
  }
  ```

- Resolved in `init` via a new `resolvePanelWidth(defaults:managed:)` helper that uses
  the existing `double(managedKey:defaultsKey:defaults:managed:fallback:)` chain
  (MDM → UserDefaults → fallback), then **clamps to 400…520**. Fallback default is
  **420** (today's value — nothing changes until the user moves the slider).

  Clamping protects against a stale UserDefaults value or an out-of-range MDM push
  producing an absurd panel.

- `isLocked("panelWidth")` works through the generic `managed.isForced` path with no
  special-casing.

**`ManagedKey` (`Sources/Hubber/Core/ManagedPreferences.swift`)**

- Add `static let panelWidth = "panelWidth"` so IT can pin the width via a managed
  profile.

**UI (`Sources/Hubber/HubberSettingsView.swift`, Appearance section)**

- Add a row next to "Row density" that mirrors the existing SLO slider
  (`HubberSettingsView.swift:44-59`):

  ```swift
  Slider(value: $settings.panelWidth, in: 400...520, step: 10)
  ```

  with a trailing `"\(Int(settings.panelWidth))pt"` readout (monospaced digits, like
  the SLO `"\(Int)h"` label) and `.disabled(settings.isLocked("panelWidth"))`.

  Range 400–520, step 10. Because `SettingsView` renders **inside** the panel
  (`HubberPopoverView.swift:160`), dragging the slider resizes the panel in real time
  — the settings UI itself reflows as the live preview.

### 2. Height — automatic, ~60% of screen

No setting, no persistence. Height is computed each time the panel opens, from the
`visibleFrame` of the screen that hosts the menu-bar item:

```
target = panelHeightFraction × visibleFrame.height     // panelHeightFraction = 0.60
maxFit = buttonFrame.minY − panelGap − visibleFrame.minY
height = min(max(target, panelMinHeight), maxFit)       // panelMinHeight = 540
```

- `target` is the desired ~60% of the screen's usable height.
- `maxFit` is the vertical space between the menu-bar button and the bottom of the
  screen — the panel hangs below the button (`y = buttonFrame.minY − height − gap`), so
  height must not exceed this or it runs off the bottom.
- The floor (`panelMinHeight = 540`) keeps laptops at today's size or slightly larger;
  `maxFit` wins on a tiny display so the panel never runs off-screen even if that means
  going below the floor.

`panelHeightFraction`, `panelMinHeight`, and `panelGap` are private constants on
`AppDelegate` for easy tuning.

**Recompute timing:** `panelOrigin(...)` already runs on every open
(`togglePanel` → `panelOrigin(relativeTo:)`). Computing height there means moving the
laptop to/from an external display "just works" — each open sizes to the current
screen. No screen-change observers needed.

Accepted trade-off (per the chosen option): with few PRs on a large display the panel
will have empty space below the list. This is intentional — size-to-content was
considered and rejected to avoid the panel resizing as data loads.

### 3. Shared AppKit plumbing (`Sources/Hubber/main.swift`)

- Replace the single `panelSize` constant with the basis for dynamic sizing: keep
  `panelGap` and `panelCornerRadius`; introduce `panelHeightFraction` and
  `panelMinHeight`; width comes from `store.settings.panelWidth`. A small default size
  is still used for the initial `panel` `contentRect` (the panel is not shown until the
  first `togglePanel`, which sets the real frame).
- The three width references in `panelOrigin(...)`
  (`main.swift:414`, `:415`, `:418`) read the current width from settings. The
  right-align + screen-clamp logic is otherwise unchanged.
- Introduce one helper, `panelFrame(relativeTo button:) -> NSRect`, that computes
  width (setting) + height (screen formula above) + origin. Used both on open and on
  live width change, so the two paths can't drift.
- **Drop the SwiftUI size pin** at `main.swift:90-91`
  (`.frame(width: Self.panelSize.width, height: Self.panelSize.height)`) so the content
  fills its host; replace with `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
- Give the hosting view and the glass view (`applyPanelBacking()`)
  `autoresizingMask = [.width, .height]` so they reflow when the panel frame changes.
- `applyPanelWidth()`: recompute `panelFrame(...)` and apply it; if the panel is
  visible, this re-anchors it under the icon. **Non-animated** so it tracks the slider
  smoothly.
- Wire a `store.settings.$panelWidth` subscription into `subscribeToStore()` (alongside
  the existing `$badgeMode` merge) → `applyPanelWidth()`.

### 4. Tests & docs

- **`SettingsStoreTests`**: `panelWidth` default is 420; round-trips through
  UserDefaults; out-of-range persisted values clamp to 400…520.
- **`SettingsStoreMDMTests`**: a forced `panelWidth` managed value wins over
  UserDefaults; `isLocked("panelWidth")` reports `true` when forced; an out-of-range
  MDM value clamps.
- **Height geometry**: extract the height formula into a pure function (e.g.
  `panelHeight(visibleFrame:buttonMinY:gap:fraction:minHeight:)`) and unit-test it:
  laptop (~558), small laptop floored to 540, large external (~850), and a tiny screen
  where `maxFit` forces below the floor. Keeps the geometry out of AppKit-only code.
- The live AppKit resize is verified by running the app — the live-preview slider is
  itself the verification.
- **Docs**: add `panelWidth` to `docs/enterprise/managed-preferences.md` so the
  managed-key catalog stays complete.

---

## Affected files

| File | Change |
|------|--------|
| `Sources/Hubber/Core/SettingsStore.swift` | `panelWidth` property + `resolvePanelWidth` + clamp |
| `Sources/Hubber/Core/ManagedPreferences.swift` | `ManagedKey.panelWidth` |
| `Sources/Hubber/HubberSettingsView.swift` | width slider row in Appearance |
| `Sources/Hubber/main.swift` | dynamic width/height, `panelFrame`, `applyPanelWidth`, autoresizing, drop content pin, subscription |
| `Tests/HubberTests/SettingsStoreTests.swift` | width default/persistence/clamp |
| `Tests/HubberTests/SettingsStoreMDMTests.swift` | width MDM force/lock/clamp |
| `Tests/HubberTests/*` (new or existing) | height geometry unit tests |
| `docs/enterprise/managed-preferences.md` | document `panelWidth` |
