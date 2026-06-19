# Tab badge mode — design

## Problem

The in-popover tab bar shows a count badge next to each tab (Reviews / Outgoing /
Drafts). Today the counts are built inline in `HubberPopoverView` with
inconsistent semantics:

- Reviews (`incoming`): total item count
- Outgoing: filtered to `ci == .failing || unresolved > 0`
- Drafts: total item count

So a healthy Outgoing tab shows no badge while Drafts always badges — the
inconsistency reads as a bug. Users should be able to choose what the badges
mean.

## Solution

Add a user setting controlling per-tab badge counts, with two modes:

- **Needs attention** (default) — badge only items needing action.
- **Total count** — badge the full item count in each tab.

This is **separate** from the existing menubar `BadgeMode` (Incoming /
Attention / Off), which governs the single menu-bar status-item badge. This new
setting governs only the in-popover tab badges.

### Count semantics

| Tab | Needs attention | Total count |
|-----|-----------------|-------------|
| Reviews (incoming) | all incoming — every request awaits you | all incoming |
| Outgoing | `ci == .failing \|\| unresolved > 0` | all outgoing |
| Drafts | `ci == .failing` | all drafts |

Reviews is identical in both modes (every incoming review awaits the viewer),
so the toggle visibly affects Outgoing and Drafts.

## Components

### `TabBadgeMode` (Models.swift)

```swift
enum TabBadgeMode: String, CaseIterable, Identifiable {
    case needsAttention   // default
    case totalCount

    var id: String { rawValue }
    var title: String { … }   // "Attention" / "Total"
}
```

### `SettingsStore.tabBadgeMode`

`@Published var tabBadgeMode: TabBadgeMode`, persisted to UserDefaults under key
`tabBadgeMode`, resolved on init with managed/MDM fallback — mirroring the
existing `badgeMode` / `incomingMode` pattern (incl. a `ManagedKey.tabBadgeMode`
entry). Default `.needsAttention`.

### `TabBadgePresentation` (Core/TabBadgePresentation.swift)

Pure, testable helper that owns the semantics:

```swift
enum TabBadgePresentation {
    static func counts(data: HubberData, mode: TabBadgeMode) -> [WorkTab: Int]
}
```

### `HubberPopoverView`

Replace the inline counts dictionary (`HubberPopoverView.swift:198`) with
`TabBadgePresentation.counts(data: store.data, mode: store.settings.tabBadgeMode)`.

### `HubberSettingsView`

New "Tab Badges" section directly under "Menubar Badge" — one segmented row
("Attention" / "Total") matching the menubar badge row's style.

## Testing

- `TabBadgePresentationTests` — both modes across the three tabs: failing vs
  healthy CI, unresolved threads present/absent, empty data → no badge.
- `SettingsStore` persistence test for `tabBadgeMode`, mirroring the existing
  badge-mode test.

## Out of scope

- The menubar `BadgeMode` is unchanged.
- No new "stale draft" heuristic — drafts badge on failing CI only.
