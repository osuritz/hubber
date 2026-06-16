# M2-B — Smart Badge & Menubar Icon Implementation Plan

> Second of four M2 PRs (A engine ✅ → **B badge/icon** → C visual → D observability). TDD, task-by-task. Branch: `feat/m2-badge` (off merged Stream A).

**Goal:** Drive the menubar badge from a configurable mode (attention-needed by default), add a badge-mode picker to Settings (MDM-lockable), and give the status item three icon states (normal / has-attention / refreshing).

**Issues:** #27 (attention-needed badge), #28 (badge mode picker), #30 (icon states).

**Architecture:** Keep the *what to show* logic pure and tested (`MenubarPresentation`), reusing `AttentionState` from Stream A; keep the `NSStatusItem` rendering/animation glue thin in `main.swift`. The status item already shows an SF Symbol + title (`main.swift:36-38`, currently a hardcoded `"5"`) — make the title dynamic and add the refreshing animation.

**Tech:** Swift 6, AppKit (`NSStatusItem`), SwiftUI settings, existing `SettingsStore` MDM priority chain.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `Sources/Hubber/Models.swift` | Add `BadgeMode` enum (`.incomingCount`, `.attentionNeeded`, `.off`) |
| Modify | `Sources/Hubber/Core/SettingsStore.swift` | `badgeMode` (string-backed, default `.attentionNeeded`, MDM key `badgeMode`) |
| Create | `Sources/Hubber/Core/MenubarPresentation.swift` | Pure `badgeCount(...)` + `state(...)` (badge text + refreshing) |
| Modify | `Sources/Hubber/main.swift` | Dynamic badge title + icon states + refreshing animation; observe store |
| Modify | `Sources/Hubber/HubberSettingsView.swift` | Badge-mode segmented picker (MDM-disabled) |
| Create | `Tests/HubberTests/MenubarPresentationTests.swift` | badgeCount per mode + state mapping |
| Modify | `Tests/HubberTests/SettingsStoreTests.swift` | `badgeMode` default + persistence |

---

## Task 1 — `BadgeMode` + `SettingsStore.badgeMode` (TDD)

`BadgeMode: String, CaseIterable, Identifiable` with cases `incomingCount`, `attentionNeeded`, `off` and `title` ("Incoming", "Attention", "Off").

**Test first** (extend `SettingsStoreTests`): default `badgeMode == .attentionNeeded`; setting it persists to UserDefaults key `badgeMode`; a UserDefaults value overrides the default. Then add `@Published var badgeMode: BadgeMode` to `SettingsStore` using the existing string MDM-priority helper (`Self.string(key: "badgeMode", ...)`) and a `didSet` persisting `rawValue`. (It is automatically MDM-lockable via the existing `isLocked("badgeMode")`.)

Commit: `feat(settings): add badgeMode (default attention-needed, MDM-lockable) (#28)`.

## Task 2 — `MenubarPresentation` pure helpers (TDD)

**Test first** (`MenubarPresentationTests`):

```swift
enum MenubarPresentation {
    /// nil = no badge (icon-only "normal" state). 0 counts collapse to nil so the badge disappears.
    static func badgeCount(mode: BadgeMode, incomingCount: Int, attentionCount: Int) -> Int? {
        switch mode {
        case .off: return nil
        case .incomingCount: return incomingCount > 0 ? incomingCount : nil
        case .attentionNeeded: return attentionCount > 0 ? attentionCount : nil
        }
    }

    struct State: Equatable { let badgeText: String?; let isRefreshing: Bool }
    static func state(badgeCount: Int?, isRefreshing: Bool) -> State {
        State(badgeText: badgeCount.map(String.init), isRefreshing: isRefreshing)
    }
}
```

Tests: `.off` → nil for any counts; `.incomingCount` → count when >0, nil when 0; `.attentionNeeded` → attentionCount when >0, nil when 0; `state` maps count→text and passes through `isRefreshing`. (`attentionCount` comes from `AttentionState` — Stream A.)

Commit: `feat(menubar): add MenubarPresentation badge/state helpers (#27, #30)`.

## Task 3 — Badge-mode picker in Settings (#28)

In `HubberSettingsView`, add a section "Menubar badge" with a segmented `Picker` bound to `$settings.badgeMode` over `BadgeMode.allCases`, `.disabled(settings.isLocked("badgeMode"))` (mirror the other MDM-lockable pickers). Build green.

Commit: `feat(ui): badge mode picker in settings (#28)`.

## Task 4 — Status item badge + icon states + refreshing animation (#27, #30)

In `main.swift`:
- Replace the hardcoded `button.title = "5"` with a value derived from `MenubarPresentation.badgeCount(mode: store.settings.badgeMode, incomingCount: store.data.incoming.count, attentionCount: AttentionState.attentionCount(data: store.data, settings: store.settings))`. Empty/nil → `button.title = ""` (icon-only "normal" state); non-nil → the count ("has-attention").
- Refreshing state (#30): while `store.isRefreshingPullRequests`, run a **subtle** repeating animation on the status button (e.g. gentle `alphaValue` pulse 0.45↔1.0 via a repeating `NSAnimation`/`Timer`, or animate `contentTintColor`); stop and restore on completion. Keep it understated.
- Observe the store so the badge/animation update on changes: subscribe to the relevant `@Published` properties (`data`, `settings.badgeMode`, `isRefreshingPullRequests`) via Combine `sink` (the `AppDelegate` already holds `store`), and call a single `updateStatusItem()` that reads `MenubarPresentation.state(...)`. Ensure updates happen on the main actor.
- Accessibility: set the button's `accessibilityValue`/`toolTip` to reflect the count (non-color cue).

Build + manual verification (menubar rendering/animation isn't unit-tested; the decision logic is covered by Task 2).

Commit: `feat(menubar): dynamic badge count + normal/attention/refreshing icon states (#27, #30)`.

---

## Acceptance (whole PR)
- `swift build` clean; `swift test` all pass (Stream A's 82 + new); `make lint` 0; `make format` idempotent.
- `badgeCount` and `state` covered by unit tests; `badgeMode` default + persistence covered. Status-item rendering verified by build + manual.
- Open PR `feat/m2-badge` → main, squash-merge.

## Self-Review Checklist
- [ ] Badge default is attention-needed; respects mode (incoming/attention/off); 0 → no badge
- [ ] `attentionCount` reused from `AttentionState` (failing CI only, each PR once)
- [ ] Badge-mode picker MDM-lockable (disabled when `isLocked("badgeMode")`)
- [ ] Refreshing animation is subtle and stops on completion; badge clears at count 0
- [ ] Status item updates reactively when data / mode / refreshing change
