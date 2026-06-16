# M3 — Notifications Implementation Plan

> Branch: `feat/m3-notifications` (off `main`). TDD task-by-task. The diff/batch logic is pure and fully unit-tested; UNUserNotificationCenter + settings UI are thin layers around it.

**Goal:** Notify the user about meaningful changes to their PRs — never on initial load, never re-firing across restarts, per-event-type opt-in, batched within a refresh, tap-to-open.

**Issues:** #34 (scheduler+baseline+diff), #35 (persist state), #36 (permission at first trigger), #37 (per-type settings UI), #38–#42 (the five events), #43 (dedup/batch).

**Architecture:** A pure `NotificationDiffer` compares the previous `ReviewSnapshot` to the current `HubberData` and emits `NotificationEvent`s (none when there is no baseline → no fire on first load, #34). A pure `NotificationBatcher` groups same-type events into one notification (#43). A `SnapshotStore` persists the snapshot to disk so restarts don't re-fire (#35). A `NotificationDispatching` protocol abstracts UNUserNotificationCenter (lazy authorization at first trigger #36, post, tap→open). `SettingsStore` gains per-type opt-in (#37). `HubberStore` wires it after each refresh.

**Tech:** Swift 6, UserNotifications (UNUserNotificationCenter), JSON snapshot in Application Support, existing `SettingsStore` MDM chain.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/Notifications/NotificationEvent.swift` | `NotificationEventType`, `NotificationEvent`, `ReviewSnapshot`/`OutgoingSnapshot` |
| Create | `Sources/Hubber/Notifications/NotificationDiffer.swift` | Pure diff + `snapshot(from:)` |
| Create | `Sources/Hubber/Notifications/NotificationBatcher.swift` | Pure event→`NotificationContent` batching (#43) |
| Create | `Sources/Hubber/Notifications/SnapshotStore.swift` | Persist/load `ReviewSnapshot` (JSON, App Support) (#35) |
| Create | `Sources/Hubber/Notifications/NotificationDispatcher.swift` | `NotificationDispatching` protocol + UN impl (#36, tap→open) |
| Modify | `Sources/Hubber/Core/SettingsStore.swift` | `notificationsEnabled` + per-type flags + MDM keys (#37) |
| Modify | `Sources/Hubber/GitHubAuth.swift` | Wire diff→batch→dispatch + snapshot persist into refresh |
| Modify | `Sources/Hubber/HubberSettingsView.swift` | Notifications section: toggles + "Enable in System Settings" (#37) |
| Modify | `Sources/Hubber/main.swift` | Set UNUserNotificationCenter delegate (tap handling) |
| Create | `Tests/HubberTests/NotificationDifferTests.swift` | Every event + no-fire-on-initial + transitions + enabled filter |
| Create | `Tests/HubberTests/NotificationBatcherTests.swift` | Single vs batched per type |
| Create | `Tests/HubberTests/SnapshotStoreTests.swift` | Round-trip + relaunch baseline |
| Modify | `Tests/HubberTests/SettingsStoreTests.swift` | Notification defaults + persistence |

---

## Task 1 — Models + `NotificationDiffer` (TDD, the core)

```swift
enum NotificationEventType: String, CaseIterable, Sendable { case newReview, reviewApproved, changesRequested, ciFailed, prMerged }

struct NotificationEvent: Equatable, Sendable {
    let type: NotificationEventType
    let prID: String; let repo: String; let number: Int; let title: String; let url: URL?
}

struct ReviewSnapshot: Codable, Equatable, Sendable {
    var incomingIDs: Set<String>
    var outgoing: [String: OutgoingSnapshot]
}
struct OutgoingSnapshot: Codable, Equatable, Sendable {
    var reviewerStates: [String: String]   // login -> ReviewerState.rawValue
    var ci: String                          // PullRequestCI.rawValue
    var mergeable: Bool
    var approved: Bool                       // approvals >= requiredApprovals (or any approved)
}
```

`NotificationDiffer.events(previous: ReviewSnapshot?, current: HubberData, enabled: Set<NotificationEventType>) -> [NotificationEvent]`:
- `previous == nil` → return `[]` (initial load never fires, #34).
- **newReview** (#38, if enabled): each `current.incoming` whose id ∉ `previous.incomingIDs`.
- **reviewApproved** (#39): each outgoing PR present in `previous.outgoing` with a reviewer now `.approved` whose previous state ≠ "approved" → one event per PR.
- **changesRequested** (#40): same shape for `.changesRequested`.
- **ciFailed** (#41): outgoing PR present before, `current.ci == .failing` and previous ci ≠ "failing".
- **prMerged** (#42): id in `previous.outgoing` but absent from current outgoing, and previous `mergeable || approved`.
- Also `NotificationDiffer.snapshot(from: HubberData) -> ReviewSnapshot`.

**Tests** (against `HubberData` fixtures): nil baseline → []; new incoming → newReview; reviewer→approved → reviewApproved (and NOT when already approved); reviewer→changesRequested; ci passing→failing → ciFailed (and not failing→failing); outgoing removed (was mergeable/approved) → prMerged (and not when it wasn't); unchanged → []; disabled type → excluded. Commit: `feat(notifications): pure NotificationDiffer + snapshot models (#34, #38-#42)`.

## Task 2 — `NotificationBatcher` (TDD, #43)

`NotificationBatcher.contents(from: [NotificationEvent]) -> [NotificationContent]` where `NotificationContent { id, title, body, url }`. Group events by `type`: count 1 → specific copy ("New review · acme/web #123"); count >1 → one batched ("3 new review requests"). Batched content's url → nil or the first PR (define + test). **Tests**: one of a type → specific; multiple of a type → single batched with the count; mixed types → one entry per type. Commit: `feat(notifications): batch same-type events into one notification (#43)`.

## Task 3 — `SnapshotStore` persistence (TDD, #35)

JSON `ReviewSnapshot` at Application Support/Hubber/notification-snapshot.json (mirror `GitHubDevelopmentFileTokenStore`). `load() -> ReviewSnapshot?`, `save(_:)`, injectable URL. **Tests**: save→load round-trip; load when absent → nil; the persisted baseline means a relaunch with identical data produces no events (load → diff(previous:loaded) → []). Commit: `feat(notifications): persist snapshot across restarts (#35)`.

## Task 4 — `SettingsStore` notification settings (TDD, #37)

Add `notificationsEnabled: Bool` (master) and per-type enabled flags; default **newReview = on, all others off**. Persist via the existing pattern; MDM-lockable via keys `notificationsEnabled` and `defaultNotificationEvents` (the latter a comma list of enabled `NotificationEventType` raw values — parse through the MDM string helper). Expose `enabledNotificationTypes: Set<NotificationEventType>` (empty when master off). **Tests**: defaults; persistence; `enabledNotificationTypes` reflects flags + master off → empty; UserDefaults override. Commit: `feat(settings): per-event-type notification opt-in (#37)`.

## Task 5 — `NotificationDispatcher` (#36, tap→open)

`protocol NotificationDispatching: Sendable { func ensureAuthorized() async -> Bool; func post(_ content: NotificationContent) async }`. Real `UNNotificationDispatcher`: `ensureAuthorized()` calls `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])` the FIRST time it's needed (lazy, #36), caches the result; `post` builds a `UNMutableNotificationContent` with `url` in `userInfo` and adds a request. A `UNUserNotificationCenterDelegate` (in main.swift / AppDelegate) handles `didReceive` → `NSWorkspace.shared.open(url)`. Denied → `post` no-ops; expose a `@Published notificationsDenied` (or query authorization status) for the settings link. **Tests**: with a fake `NotificationDispatching`, assert the coordinator calls `ensureAuthorized` before the first `post` and does NOT post when authorization is denied (logic-level; the real UN layer is manual-verify). Commit: `feat(notifications): UNUserNotificationCenter dispatcher with lazy authorization (#36)`.

## Task 6 — Notifications settings UI (#37)

In `HubberSettingsView`, add a "Notifications" section: a master toggle + a toggle per event type (labels: "New review requested", "Review approved", "Changes requested", "CI failed", "PR merged"), each `.disabled(settings.isLocked(...))`. When authorization is denied, show an "Enable in System Settings" row/link (`NSWorkspace.open` of `x-apple.systempreferences:com.apple.preference.notifications`). Build + manual. Commit: `feat(ui): Notifications settings section (#37)`.

## Task 7 — Wire into the refresh cycle (#34)

In `HubberStore`: hold a `ReviewSnapshot?` baseline loaded from `SnapshotStore` at init (nil if none → first run won't fire). After each successful refresh, compute `events = NotificationDiffer.events(previous: baseline, current: data, enabled: settings.enabledNotificationTypes)`; if non-empty and authorized, `NotificationBatcher.contents(from:)` → dispatch each; then set `baseline = snapshot(from: data)` and persist via `SnapshotStore`. Respect per-tab partial failures: only update the snapshot portions for tabs that succeeded (don't drop baseline for a failed tab → avoids false "merged" on a fetch error). Inject `dispatcher`/`snapshotStore` for tests. **Test**: a `HubberStore`-level (or extracted-coordinator) test that a second refresh with a new incoming PR posts exactly one notification via a spy dispatcher, and the first refresh posts none. Commit: `feat(notifications): run diff→batch→dispatch on each refresh and persist baseline (#34)`.

---

## Acceptance (whole PR)
- `swift build` clean; `swift test` all pass (M2's 172 + new); `make lint` 0; `make format` idempotent.
- Differ / batcher / snapshot / settings covered by unit tests; UN authorization + tap verified by build + manual.
- No fire on initial load or across restarts; only `newReview` on by default; events batch within a cycle; tap opens the PR.
- Open PR(s) → main, squash-merge.

## Self-Review Checklist
- [ ] Initial load + restart never fire (baseline gating #34/#35)
- [ ] Five events fire on the correct transitions; respect enabled set
- [ ] Same-type events batch into one notification (#43)
- [ ] Authorization requested lazily at first trigger; denied → no-op + Settings link (#36)
- [ ] Defaults: newReview on, rest off; MDM keys honored (#37)
- [ ] Tap opens the PR; per-tab fetch failure doesn't corrupt the baseline
