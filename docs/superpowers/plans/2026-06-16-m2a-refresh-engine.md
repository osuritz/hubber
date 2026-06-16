# M2-A — Adaptive Refresh Engine Implementation Plan

> First of four focused M2 PRs (A engine → B badge/icon → C visual → D observability). Execute task-by-task with TDD. Branch: `feat/m2-engine`.

**Goal:** Replace `HubberStore`'s fixed 5-minute refresh loop with an adaptive `RefreshScheduler` driven by a pure cadence function, add GitHub rate-limit backoff with a footer status message, refresh immediately on system wake, and wire ⌘R to manual refresh.

**Issues:** #24 (RefreshScheduler), #25 (rate-limit backoff), #26 (sleep/wake), #29 (⌘R).

**Architecture:** Keep the *decision* logic pure and fully unit-tested; keep the timer/system glue thin and injectable. `RefreshScheduler` (@MainActor) owns a single rescheduling task; on each tick it asks `HubberStore` for a `RefreshContext`, runs the refresh, then reschedules using `RefreshCadence.interval(for:)`. System idle and the clock are injected so the scheduler is testable without real timers.

**Tech:** Swift 6, AppKit (`NSWorkspace.didWakeNotification`, idle query), SwiftUI (`.keyboardShortcut`), existing `MockURLProtocol` for rate-limit tests.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/Core/RefreshCadence.swift` | `RefreshContext` + pure `interval(for:)` priority function |
| Create | `Sources/Hubber/Core/AttentionState.swift` | `attentionCount`/`hasUrgentSLO`/`isAllGreen` from `HubberData`+`SettingsStore` (shared with Stream B badge) |
| Create | `Sources/Hubber/Core/RefreshScheduler.swift` | @MainActor rescheduling task; injectable idle + clock |
| Create | `Sources/Hubber/Core/SystemIdleProvider.swift` | Real machine-idle query (IOKit `HIDIdleTime`) behind a tiny protocol |
| Modify | `Sources/Hubber/GitHubAuth.swift` | Replace fixed loop with `RefreshScheduler`; `isPopoverOpen`; rate-limit state + footer message; wake refresh hook |
| Modify | `Sources/Hubber/GitHub/GitHubProvider.swift` | Detect 429 / 403+`x-ratelimit-remaining:0` → throw `rateLimited` |
| Modify | `Sources/Hubber/GitHubAuth.swift` | Add `GitHubAuthError.rateLimited(retryAfter:)` |
| Modify | `Sources/Hubber/main.swift` | Set `isPopoverOpen`; register `didWakeNotification` → refresh; ⌘R path |
| Modify | `Sources/Hubber/HubberPopoverView.swift` | ⌘R keyboard shortcut; footer rate-limit message |
| Modify | `Sources/Hubber/ReviewSLOPresentation.swift` | Footer rate-limit message formatter (pure, testable) |
| Create | `Tests/HubberTests/RefreshCadenceTests.swift` | Priority table + precedence |
| Create | `Tests/HubberTests/AttentionStateTests.swift` | urgency / all-green / attention count |
| Create | `Tests/HubberTests/RefreshSchedulerTests.swift` | reset / refreshNow / reschedule with injected clock+idle |
| Modify | `Tests/HubberTests/GitHubProviderTests.swift` | rate-limit detection (429, 403) |

---

## Task 1 — `RefreshCadence` pure function (TDD)

**Test first** (`RefreshCadenceTests`): assert the priority table and precedence. Cadence (highest wins):

| Condition | Interval |
|---|---|
| Rate-limited | 900 s (must win — we have to back off) |
| Any PR within 20% of SLO budget (urgent) | 30 s |
| Popover open | 60 s |
| Machine idle **and** all-green | 900 s |
| Otherwise (background normal) | 300 s |

```swift
struct RefreshContext: Equatable {
    var isRateLimited = false
    var hasUrgentSLO = false
    var isPopoverOpen = false
    var isMachineIdle = false
    var isAllGreen = false
}

enum RefreshCadence {
    static func interval(for ctx: RefreshContext) -> TimeInterval {
        if ctx.isRateLimited { return 15 * 60 }
        if ctx.hasUrgentSLO { return 30 }
        if ctx.isPopoverOpen { return 60 }
        if ctx.isMachineIdle, ctx.isAllGreen { return 15 * 60 }
        return 5 * 60
    }
}
```

Tests: each row in isolation; `isRateLimited` overrides `hasUrgentSLO`; `hasUrgentSLO` beats `isPopoverOpen`; `isPopoverOpen` beats background; idle-but-not-all-green → 300; all-green-but-not-idle → 300. Commit: `feat(refresh): add pure RefreshCadence priority function (#24)`.

## Task 2 — `AttentionState` (TDD)

Shared logic also used by Stream B's badge (#27). **Test first** against `HubberData` fixtures + a `SettingsStore`.

- `attentionItems(data:settings:) -> Set<String>`: distinct PR ids needing action now = every incoming review **+** outgoing with **failing** CI (`.failing` only, not `.running`) **+** outgoing with `unresolved > 0`. One PR counts once.
- `attentionCount` = `attentionItems.count`.
- `isAllGreen` = `attentionCount == 0`.
- `hasUrgentSLO(data:settings:)`: `settings.sloEnabled` **and** any incoming review with `assignedAgoHours >= 0.8 * settings.sloHours(for: repo)` (≥80% elapsed = within 20% of budget, includes overdue).

Tests: all-green sample → count 0, isAllGreen true; a failing-CI outgoing → counted; running-CI outgoing → not counted; incoming near SLO → hasUrgentSLO true; SLO disabled → hasUrgentSLO false. Commit: `feat(refresh): add AttentionState (attention count, all-green, urgent SLO) (#24, #27)`.

## Task 3 — Rate-limit detection (TDD)

**Test first** (`GitHubProviderTests`): MockURLProtocol returns **429** with `Retry-After: 30` → fetch throws `GitHubAuthError.rateLimited(retryAfter: 30)`; and **403** with `x-ratelimit-remaining: 0` → `.rateLimited`. A plain 403 without that header stays `.github(...)`.

- Add `case rateLimited(retryAfter: TimeInterval?)` to `GitHubAuthError` (+ `errorDescription`).
- In `GitHubProvider.graphQL`, before the generic non-2xx throw: if `status == 429` **or** (`status == 403` and `x-ratelimit-remaining == "0"`), parse `Retry-After` (seconds) and throw `.rateLimited`.

Commit: `feat(github): detect GitHub rate limiting (429/403) and surface retryAfter (#25)`.

## Task 4 — `RefreshScheduler` + HubberStore integration (TDD where pure)

`SystemIdleProvider` — protocol `MachineIdleProviding { var isIdle: Bool { get } }` + a real impl querying IOKit `HIDIdleTime` against a threshold (e.g. ≥ 5 min idle). Injectable.

`RefreshScheduler` (@MainActor):
```swift
@MainActor final class RefreshScheduler {
    init(idle: MachineIdleProviding = SystemIdleProvider(),
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) })
    func start(context: @escaping @MainActor () -> RefreshContext, refresh: @escaping @MainActor () async -> Void)
    func reset()        // ⌘R / wake: cancel current wait, refresh now, reschedule from completion
    func stop()
}
```
Loop: `refresh()` → compute `interval(for: context())` → `sleep(interval)` → repeat; `reset()` cancels the in-flight sleep and re-enters at `refresh()`.

Integrate into `HubberStore`: replace `startPullRequestRefreshLoop`'s fixed `Task.sleep(5*60)` with the scheduler. `HubberStore` builds the `RefreshContext` (uses `AttentionState` + `isPopoverOpen` + injected idle) and supplies `refreshPullRequestsFromGitHub` as the refresh closure. On `GitHubAuthError.rateLimited` inside the refresh, set `rateLimitedUntil`/message (Task 6) so the next computed context has `isRateLimited = true`. Add `@Published var isPopoverOpen` (default false). `stop()` on sign-out / sessionExpired.

Tests (`RefreshSchedulerTests`): inject a fake `sleep` that records requested intervals and a controllable idle; assert the scheduler requests the interval returned by `RefreshCadence` for a given context, that `reset()` triggers an immediate refresh, and that `stop()` halts. (Avoid real timers.) Commit: `feat(refresh): adaptive RefreshScheduler replacing fixed loop (#24)`.

## Task 5 — Sleep/wake immediate refresh (#26)

In `main.swift` (AppDelegate), observe `NSWorkspace.shared.notificationCenter` `NSWorkspace.didWakeNotification` → call `store.refreshPullRequests()` (which routes through `scheduler.reset()`). Remove observer on teardown. Verified by build + manual (system notification not unit-tested). Commit: `feat(refresh): refresh immediately on system wake (#26)`.

## Task 6 — ⌘R + footer rate-limit message (#25 UI, #29)

- `ReviewSLOPresentation.rateLimitFooter(secondsRemaining:) -> String` (pure): `"Rate limited — next refresh in \(m)m"`. **Test** the formatter.
- `HubberStore`: expose `rateLimitMessage: String?` derived from `rateLimitedUntil` (set when a refresh throws `.rateLimited`, cleared on success). Footer in `HubberPopoverView` shows it when present.
- ⌘R: in `HubberPopoverView`, a `.keyboardShortcut("r", modifiers: .command)` control calling `store.refreshPullRequests()`; ensure manual refresh path calls `scheduler.reset()` (schedule next tick from completion).

Commit: `feat(ui): wire ⌘R refresh and rate-limit footer status (#25, #29)`.

---

## Acceptance (whole PR)
- `swift build` clean; `swift test` all pass (M1's 48 + new); `make lint` 0 violations; `make format` idempotent.
- `RefreshCadence`, `AttentionState`, rate-limit detection, and the footer formatter are covered by unit tests. Scheduler decision path tested with injected clock/idle. Sleep/wake + ⌘R verified by build + manual.
- Open PR `feat/m2-engine` → main, squash-merge.

## Self-Review Checklist
- [ ] Cadence priority matches the PRD table; rate-limit forces 15 min
- [ ] Attention/all-green/urgent-SLO logic shared and reused by Stream B
- [ ] Rate-limit detection covers 429 and 403+header; `Retry-After` parsed
- [ ] Fixed 5-min loop fully replaced; scheduler stops on sign-out / sessionExpired
- [ ] ⌘R resets timer from completion; footer shows rate-limit countdown
- [ ] Wake triggers immediate refresh
