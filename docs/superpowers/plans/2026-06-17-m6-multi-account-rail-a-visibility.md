# M6 Multi-Account — Rail A: Connection Visibility + Aggregator Determinism (#61) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Branch: `feat/m6-multi-account-ui` (off `main`). TDD task-by-task; commit per green task. Gate with **`make ci`** (build + `swift test` + swiftlint + `swiftformat --lint`); the `.githooks/pre-push` hook runs it on push (CI manual-only).

**Goal:** Add per-account show/hide visibility (Calendar/Fantastical-style) so the unified inbox and menu-bar badge reflect only *visible* connections, persisted across launches — and make the cross-connection baseline merge deterministic (#5).

**Architecture:** A pure `ConnectionVisibility` value type (a set of hidden `ConnectionID`s) is persisted by `SettingsStore` and consulted by a new visibility-aware `ConnectionAggregator.aggregate(_:visibility:)`. `HubberStore.recomputeAggregate()` routes its connections through it, so `data` (and the badge derived from it) drop hidden accounts. Separately, `ConnectionAggregator.mergeOutgoingSnapshots` gains a deterministic reviewer-state tie-break so the union baseline is order-independent.

**Tech Stack:** Swift 6.3, SPM, XCTest, SwiftUI/Combine, `UserDefaults` persistence.

**Issues:** Refs #61, #80. Fixes #5 (reviewer-state merge determinism). This is **Rail A** of the #61 multi-account build; the design spec is `docs/superpowers/specs/2026-06-17-m6-multi-account-ui-design.md`. Rail B (PAT credential path + connection factory + `restoreAllConnections()` launch wiring + `notifyHiddenAccounts`) and Phase 2 (the account-menu/add-account/Settings UI) are separate plans.

---

## Coordinator decisions (do not relitigate)

1. **`ConnectionVisibility` is a pure value type** keyed by `ConnectionID` (Codable). Persistence lives in `SettingsStore` (mirrors how every other setting is persisted). Default: a connection not in the hidden set is **visible** (new accounts appear by default).
2. **Visibility filters the display aggregate and the badge, but NOT notifications.** This plan only does the display/badge filtering. Notification routing (`notifyHiddenAccounts`, default — hidden accounts still notify) is coupled to the notification pipeline and lands in **Rail B**, not here.
3. **Filtering is a pure function.** `ConnectionAggregator.aggregate(_ items:visibility:)` takes `(id, data)` pairs so it is unit-testable without building `Connection`s or starting schedulers (a `RefreshScheduler` with a real provider would hang the bundle-less xctest host).
4. **#5 tie-break = most-advanced reviewer state wins, deterministically.** Priority `changesRequested > approved > commented > pending`. The merge becomes commutative/associative (order-independent), so the union baseline no longer depends on dict iteration order. Documented as "a reviewer that has progressed in any baseline is treated as already-observed."

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/Core/ConnectionVisibility.swift` | Pure value type: hidden-`ConnectionID` set + `isVisible`/`setting` |
| Modify | `Sources/Hubber/Core/SettingsStore.swift` | `@Published connectionVisibility` + UserDefaults persistence |
| Modify | `Sources/Hubber/Core/ConnectionAggregator.swift` | `aggregate(_:visibility:)` overload; deterministic `mergeOutgoingSnapshots` reviewer tie-break (#5) |
| Modify | `Sources/Hubber/GitHubAuth.swift` | `HubberStore.recomputeAggregate()` routes via visibility; add `setConnectionVisible(_:_:)` |
| Create | `Tests/HubberTests/ConnectionVisibilityTests.swift` | Value-type + persistence + visibility-aware aggregate tests |
| Modify | `Tests/HubberTests/ConnectionAggregatorTests.swift` | #5 determinism/commutativity tests |

---

## Tasks

### Task 1 — `ConnectionVisibility` value type (TDD)

**Files:**
- Create: `Sources/Hubber/Core/ConnectionVisibility.swift`
- Test: `Tests/HubberTests/ConnectionVisibilityTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/HubberTests/ConnectionVisibilityTests.swift
import Foundation
import SwiftUI
import XCTest
@testable import Hubber

final class ConnectionVisibilityTests: XCTestCase {
    private let gh = ConnectionID.gitHubDotCom(login: "osuritz")
    private let gl = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")

    func testDefaultEverythingVisible() {
        let v = ConnectionVisibility()
        XCTAssertTrue(v.isVisible(gh))
        XCTAssertTrue(v.isVisible(gl))
    }

    func testHidingThenShowing() {
        let hidden = ConnectionVisibility().setting(gl, visible: false)
        XCTAssertTrue(hidden.isVisible(gh))
        XCTAssertFalse(hidden.isVisible(gl))

        let shown = hidden.setting(gl, visible: true)
        XCTAssertTrue(shown.isVisible(gl))
    }

    func testCodableRoundTrip() throws {
        let v = ConnectionVisibility().setting(gl, visible: false)
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(ConnectionVisibility.self, from: data)
        XCTAssertEqual(decoded, v)
        XCTAssertFalse(decoded.isVisible(gl))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConnectionVisibilityTests`
Expected: FAIL — `cannot find 'ConnectionVisibility' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Hubber/Core/ConnectionVisibility.swift
import Foundation

/// Which connections are shown in the unified inbox. A connection NOT in `hidden` is visible,
/// so newly-added accounts appear by default. Pure value type — persistence lives in SettingsStore.
struct ConnectionVisibility: Equatable, Codable, Sendable {
    private(set) var hidden: Set<ConnectionID>

    init(hidden: Set<ConnectionID> = []) {
        self.hidden = hidden
    }

    func isVisible(_ id: ConnectionID) -> Bool {
        !hidden.contains(id)
    }

    /// Returns a copy with `id` shown or hidden.
    func setting(_ id: ConnectionID, visible: Bool) -> ConnectionVisibility {
        var next = hidden
        if visible { next.remove(id) } else { next.insert(id) }
        return ConnectionVisibility(hidden: next)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConnectionVisibilityTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/ConnectionVisibility.swift Tests/HubberTests/ConnectionVisibilityTests.swift
git commit -m "feat(m6): ConnectionVisibility value type (#61)"
```

---

### Task 2 — `SettingsStore` persists visibility (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/SettingsStore.swift` (add property + init resolution + persistence)
- Test: `Tests/HubberTests/ConnectionVisibilityTests.swift`

- [ ] **Step 1: Write the failing test** (add to `ConnectionVisibilityTests`)

```swift
    @MainActor
    func testSettingsStorePersistsVisibilityAcrossInstances() throws {
        let suite = "ConnectionVisibilityTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.connectionVisibility.isVisible(gl)) // default visible

        store.connectionVisibility = store.connectionVisibility.setting(gl, visible: false)

        // A fresh store over the same defaults sees the hidden connection.
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertFalse(reopened.connectionVisibility.isVisible(gl))
        XCTAssertTrue(reopened.connectionVisibility.isVisible(gh))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConnectionVisibilityTests/testSettingsStorePersistsVisibilityAcrossInstances`
Expected: FAIL — `value of type 'SettingsStore' has no member 'connectionVisibility'`.

- [ ] **Step 3: Add the property + persistence to `SettingsStore`**

Add this published property after the provider-access block (around `SettingsStore.swift:87`, before `// MARK: - Notifications`):

```swift
    // MARK: - Connection visibility (#61)

    /// Which connections are shown in the unified inbox. Persisted as JSON in UserDefaults.
    @Published var connectionVisibility: ConnectionVisibility {
        didSet {
            if let data = try? JSONEncoder().encode(connectionVisibility) {
                defaults.set(data, forKey: "connectionVisibility")
            }
        }
    }
```

In `init` (after `providerAllowlist = ...`, around `SettingsStore.swift:174`):

```swift
        connectionVisibility = Self.resolveConnectionVisibility(defaults: defaults)
```

Add the resolver near the other `resolve*` helpers (e.g. after `resolveProviderAllowlist`):

```swift
    /// Loads persisted connection visibility (UserDefaults only — not MDM-managed).
    private static func resolveConnectionVisibility(defaults: UserDefaults) -> ConnectionVisibility {
        guard
            let data = defaults.data(forKey: "connectionVisibility"),
            let value = try? JSONDecoder().decode(ConnectionVisibility.self, from: data)
        else { return ConnectionVisibility() }
        return value
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConnectionVisibilityTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/SettingsStore.swift Tests/HubberTests/ConnectionVisibilityTests.swift
git commit -m "feat(m6): persist connection visibility in SettingsStore (#61)"
```

---

### Task 3 — Visibility-aware aggregate + badge filtering (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/ConnectionAggregator.swift` (new overload)
- Modify: `Sources/Hubber/GitHubAuth.swift` (`HubberStore.recomputeAggregate` + `setConnectionVisible`)
- Test: `Tests/HubberTests/ConnectionVisibilityTests.swift`

- [ ] **Step 1: Write the failing test** (add to `ConnectionVisibilityTests`)

```swift
    func testVisibilityAwareAggregateDropsHiddenConnections() {
        let ghData = HubberData(
            incoming: [Self.incoming(id: "gh-1", repo: "acme/api")],
            outgoing: [], drafts: []
        )
        let glData = HubberData(
            incoming: [Self.incoming(id: "gl-1", repo: "grp/proj")],
            outgoing: [], drafts: []
        )
        let items: [(id: ConnectionID, data: HubberData)] = [(gh, ghData), (gl, glData)]

        // All visible → both incoming items.
        let all = ConnectionAggregator.aggregate(items, visibility: ConnectionVisibility())
        XCTAssertEqual(all.incoming.map(\.id).sorted(), ["gh-1", "gl-1"])

        // Hide GitLab → only the GitHub item.
        let hidden = ConnectionVisibility().setting(gl, visible: false)
        let filtered = ConnectionAggregator.aggregate(items, visibility: hidden)
        XCTAssertEqual(filtered.incoming.map(\.id), ["gh-1"])
    }

    private static func incoming(id: String, repo: String) -> IncomingReview {
        IncomingReview(
            id: id, repo: repo, number: 1, title: "t", url: nil,
            author: GitHubUser(login: "a", initials: "A", color: .gray),
            sloClockStart: Date(timeIntervalSince1970: 0),
            additions: 0, deletions: 0, files: 0
        )
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConnectionVisibilityTests/testVisibilityAwareAggregateDropsHiddenConnections`
Expected: FAIL — `extra argument 'visibility' in call` (no such overload).

- [ ] **Step 3: Add the visibility-aware overload**

In `Sources/Hubber/Core/ConnectionAggregator.swift`, add inside `enum ConnectionAggregator` (after the existing `aggregate(_:)`):

```swift
    /// Aggregates only the visible connections' data. Pure — takes (id, data) pairs so it is
    /// testable without building `Connection`s / starting schedulers.
    static func aggregate(
        _ items: [(id: ConnectionID, data: HubberData)],
        visibility: ConnectionVisibility
    ) -> HubberData {
        aggregate(items.filter { visibility.isVisible($0.id) }.map(\.data))
    }
```

- [ ] **Step 4: Route `HubberStore` through it + add the toggle**

In `Sources/Hubber/GitHubAuth.swift`, replace the body of `recomputeAggregate()` (currently `data = ConnectionAggregator.aggregate(connections.map(\.data))`):

```swift
    private func recomputeAggregate() {
        data = ConnectionAggregator.aggregate(
            connections.map { (id: $0.id, data: $0.data) },
            visibility: settings.connectionVisibility
        )
        isRefreshingPullRequests = connections.contains { $0.isRefreshingPullRequests }
    }
```

Add a toggle method (near `setPopoverOpen`):

```swift
    /// Shows or hides a connection in the unified inbox + badge. Persisted via SettingsStore.
    func setConnectionVisible(_ id: ConnectionID, _ visible: Bool) {
        settings.connectionVisibility = settings.connectionVisibility.setting(id, visible: visible)
        recomputeAggregate()
    }
```

- [ ] **Step 5: Run tests to verify they pass + the suite is green**

Run: `swift test --filter ConnectionVisibilityTests` then `swift test --filter HubberStore`
Expected: PASS — visibility tests green; existing `HubberStore`/aggregate tests unaffected (single-connection default has nothing hidden → identical output).

- [ ] **Step 6: Commit**

```bash
git add Sources/Hubber/Core/ConnectionAggregator.swift Sources/Hubber/GitHubAuth.swift Tests/HubberTests/ConnectionVisibilityTests.swift
git commit -m "feat(m6): unified inbox + badge honor per-connection visibility (#61)"
```

---

### Task 4 — Deterministic reviewer-state baseline merge (#5) (TDD)

**Files:**
- Modify: `Sources/Hubber/Core/ConnectionAggregator.swift` (`mergeOutgoingSnapshots` reviewer tie-break)
- Test: `Tests/HubberTests/ConnectionAggregatorTests.swift`

- [ ] **Step 1: Write the failing test** (add to `ConnectionAggregatorTests`)

```swift
    // #5 — conflicting non-pending reviewer states must merge deterministically (order-independent),
    // most-advanced (changesRequested > approved > commented > pending) winning.
    func testMergedBaselineReviewerStateIsDeterministic() {
        func snap(_ state: ReviewerState) -> OutgoingSnapshot {
            OutgoingSnapshot(
                reviewerStates: ["alice": state.rawValue],
                ci: PullRequestCI.passing.rawValue,
                mergeable: true, approved: false,
                repo: "acme/api", number: 7, title: "t", url: nil
            )
        }
        let a = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-7": snap(.approved)])
        let b = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-7": snap(.changesRequested)])

        let ab = ConnectionAggregator.mergedBaseline([a, b]).outgoing["pr-7"]
        let ba = ConnectionAggregator.mergedBaseline([b, a]).outgoing["pr-7"]

        XCTAssertEqual(ab?.reviewerStates["alice"], ReviewerState.changesRequested.rawValue)
        XCTAssertEqual(ab?.reviewerStates["alice"], ba?.reviewerStates["alice"]) // order-independent
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConnectionAggregatorTests/testMergedBaselineReviewerStateIsDeterministic`
Expected: FAIL — current merge keeps the first non-pending state, so `mergedBaseline([a,b])` yields `approved`, not `changesRequested`.

- [ ] **Step 3: Make the reviewer-state merge deterministic**

In `Sources/Hubber/Core/ConnectionAggregator.swift`, replace the reviewer-state loop in `mergeOutgoingSnapshots` (the `for (login, state) in second.reviewerStates { ... }` block) with:

```swift
        var mergedReviewerStates = first.reviewerStates
        for (login, state) in second.reviewerStates {
            if let existing = mergedReviewerStates[login] {
                mergedReviewerStates[login] = Self.mostAdvancedReviewerState(existing, state)
            } else {
                mergedReviewerStates[login] = state
            }
        }
```

And add the helpers (private, near the bottom of the enum):

```swift
    /// Deterministic, order-independent tie-break for a reviewer observed in two baselines:
    /// the most-advanced state wins, so a reviewer that has progressed in ANY baseline is
    /// treated as already-observed and won't spuriously re-notify.
    private static func mostAdvancedReviewerState(_ a: String, _ b: String) -> String {
        reviewerStatePriority(a) >= reviewerStatePriority(b) ? a : b
    }

    private static func reviewerStatePriority(_ raw: String) -> Int {
        switch raw {
        case ReviewerState.changesRequested.rawValue: 3
        case ReviewerState.approved.rawValue: 2
        case ReviewerState.commented.rawValue: 1
        default: 0 // pending / unknown
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConnectionAggregatorTests`
Expected: PASS — new determinism test plus all existing aggregator tests (pending→non-pending still upgrades, since any non-pending out-ranks pending).

- [ ] **Step 5: Commit**

```bash
git add Sources/Hubber/Core/ConnectionAggregator.swift Tests/HubberTests/ConnectionAggregatorTests.swift
git commit -m "fix(m6): deterministic reviewer-state baseline merge (#5)"
```

---

### Task 5 — Full gate

- [ ] **Step 1: Run the gate**

Run: `make ci`
Expected: build + `swift test` all green (prior suite + ~8 new tests); swiftlint 0; `swiftformat --lint` clean. If swiftformat flags new files, run `swiftformat .` and re-stage.

---

## Acceptance (whole plan)

- `make ci` green; existing suite unaffected (single-connection default hides nothing → identical aggregate/badge).
- `ConnectionVisibility` is a pure, Codable value type; `SettingsStore` persists it across instances; new connections default visible.
- The unified inbox `data` and the menu-bar badge (which derives from `data`) drop hidden connections; `HubberStore.setConnectionVisible(_:_:)` toggles + persists.
- `mergeOutgoingSnapshots` reviewer-state merge is deterministic/order-independent (#5), most-advanced winning; pending still upgrades to any non-pending.
- **Deferred to Rail B (next plan):** PAT credential path, connection factory, `restoreAllConnections()` launch wiring, `notifyHiddenAccounts` (notifications for hidden accounts). **Phase 2:** account menu UI, add-account flow, Settings → Accounts.

## Self-Review Checklist
- [ ] `ConnectionVisibility` default-visible semantics; Codable round-trips; persisted under `"connectionVisibility"`.
- [ ] `aggregate(_:visibility:)` is pure (takes `(id, data)`), so tests need no `Connection`/scheduler (no hang).
- [ ] `recomputeAggregate()` passes `settings.connectionVisibility`; badge auto-follows `data` (no separate badge change needed).
- [ ] #5 merge is commutative (priority max), pending always loses to non-pending; existing pending-upgrade behavior preserved.
- [ ] Names consistent: `ConnectionVisibility`, `isVisible`, `setting(_:visible:)`, `connectionVisibility`, `aggregate(_:visibility:)`, `setConnectionVisible`, `mostAdvancedReviewerState`.
