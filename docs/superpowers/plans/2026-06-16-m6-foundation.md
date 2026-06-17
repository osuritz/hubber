# M6 Foundation — Connection Model + Token-Storage Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (fresh delegate per task) to implement this task-by-task. Steps use checkbox (`- [ ]`) tracking. TDD throughout; commit after each green task (`swift build && swift test && make lint && make format`). Branch `feat/m6-foundation` off `main`. One PR → main; **watch CI green on `macos-26` before squash-merge** (locally-green ≠ CI-green; guard `UNUserNotificationCenter` behind `Bundle.main.bundleURL.pathExtension == "app"`).

**Goal:** Generalize Hubber from single-tenant to a **set of connections** so two GitHub accounts (personal + work) coexist with isolated tokens, notification baselines, schedulers, and error state — validated entirely at the model level by the QA plan's Phase-1 acceptance gate. No new "add account" UI here (that is #61); the existing single-connection UI keeps working unchanged.

**Architecture:** Extract a per-connection `Connection` (`@MainActor ObservableObject`) that owns one account's `{ provider, identity, tokenStore, snapshotStore, scheduler, authState, data, baseline, errors }`. Reshape `HubberStore` into a **coordinator** over `[Connection]` that aggregates their data (union + dedup by id) and forwards a single-connection-shaped surface to the existing views. Storage keys (Keychain item, snapshot file) derive deterministically from a `ConnectionID = (provider, host, login)`.

**Tech Stack:** Swift 6.3 / SwiftUI + AppKit, XCTest, `MockURLProtocol`, `InMemoryManagedPreferences`, SPM. CI `macos-26`.

**Issues:** Closes #81 (foundation). Refs #80 (epic). Lays the rails consumed by #60 (GitLab), #82 (GHES), #61 (multi-account UI).

---

## Coordinator decisions (do not relitigate)

1. **Connection identity is deterministic:** `ConnectionID = (provider, host, login)`, all lowercased. It keys the Keychain item, the snapshot file, the scheduler, and dedup. A login rename orphans the old keys (acceptable; revisit only if churn shows up). *(Locked with the user 2026-06-16.)*
2. **Dedup by PR node id, keep earliest `sloClockStart`** for incoming; first occurrence for outgoing/drafts. Done in a pure `ConnectionAggregator`.
3. **One shared `SettingsStore`** across all connections (per-connection settings is a later refinement). `Connection` reads the injected shared `settings`.
4. **`CodeHostAuthServicing` is introduced now as the connection-facing auth seam** holding the *generic* surface (`refresh`, `fetchAuthenticatedUser`), which `GitHubAuthService` conforms to. GitHub **device-flow** methods (`startDeviceFlow`, `pollForToken`) stay on the GitHub-specific `GitHubDeviceFlowServicing: CodeHostAuthServicing`. The GitLab **PAT** credential path is added to this same seam in #60 — **do not** build it here.
5. **GHES base-URL parameterization is #82, not here.** This plan stays on `github.com`. Do not touch the hardcoded hosts in `GitHubProvider`/`GitHubAuthService` except where the `Connection` passes them through unchanged.
6. **Single-connection UI is preserved.** The coordinator exposes a `primaryConnection` whose `authState` drives the existing header/sign-in chrome; aggregated `data` (1..N connections) drives the lists. The real account/provider switcher that surfaces >1 connection is **#61** — out of scope here.
7. **Notification model = per-connection snapshot files + a coordinator diff over aggregated data.** Each `Connection` persists its **own** snapshot file (isolation, sign-out cleanup). The notification *diff* runs once over **aggregated current data** vs the **union of all connections' baselines** (dedup by id), so the same PR under two accounts fires exactly one notification and a 2nd connection never false-fires a PR the 1st already knew. After dispatch, each connection advances **its own** baseline file (preserving the existing succeeded-tabs-only partial-failure logic in `HubberStoreNotifications.swift`).
8. **Migration is mandatory.** Existing users have one token at the legacy Keychain `account = "github-app-user-token"` and one snapshot at `notification-snapshot.json`. On first launch with no connection registry, migrate the legacy token (its cached `login` yields the `ConnectionID`) and rename the legacy snapshot to the derived path. Never silently drop a user's session or re-baseline (which would notification-storm).
9. **Partial failure = last-good data + per-connection error.** A failed connection keeps its previous `data` and sets its own `incomingError`/etc.; it is never replaced with empty data, and its baseline is never dropped. Aggregation simply unions whatever each connection currently holds.

---

## Authoritative contract (types the tasks must converge on)

```swift
// Sources/Hubber/Core/ConnectionID.swift
struct ConnectionID: Hashable, Codable, CustomStringConvertible, Sendable {
    let provider: String   // "github" (… "gitlab" in #60)
    let host: String       // "github.com" (… GHES host in #82)
    let login: String      // viewer login, lowercased
    init(provider: String, host: String, login: String) {
        self.provider = provider.lowercased()
        self.host = host.lowercased()
        self.login = login.lowercased()
    }
    var description: String { "\(provider):\(host):\(login)" }
    /// Keychain-account / filename-safe slug, e.g. "github_github.com_personal".
    var slug: String  // provider_host_login with non-[a-z0-9._-] replaced by '-'
    static func gitHubDotCom(login: String) -> ConnectionID
        { ConnectionID(provider: "github", host: "github.com", login: login) }
}
```

```swift
// Keychain isolation — Sources/Hubber/GitHubAuth.swift
// service stays constant; account becomes the ConnectionID slug.
final class GitHubKeychainTokenStore: GitHubTokenStoring {
    private let service = "com.osuritz.hubber.github-auth"
    private let account: String              // was constant "github-app-user-token"
    init(account: String)                    // pass connectionID.slug
    static let legacyAccount = "github-app-user-token"   // migration source
}
// GitHubTokenStore.makeDefault() gains: makeStore(for: ConnectionID) -> any GitHubTokenStoring
```

```swift
// Per-connection snapshot — Sources/Hubber/Notifications/SnapshotStore.swift
init(connectionID: ConnectionID)             // path: notification-snapshot-<slug>.json
func delete()                                // for sign-out (MC-NOTIF-05)
static let legacySnapshotURL: URL            // migration source (notification-snapshot.json)
```

```swift
// Auth seam — Sources/Hubber/GitHubAuth.swift
protocol CodeHostAuthServicing: Sendable {
    func refresh(_ token: GitHubStoredToken) async throws -> GitHubStoredToken
    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser
}
protocol GitHubDeviceFlowServicing: CodeHostAuthServicing {
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization
    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> GitHubStoredToken
}
// GitHubAuthServicing becomes a typealias/refinement == GitHubDeviceFlowServicing; GitHubAuthService conforms.
// SpyGitHubAuthService keeps conforming (no test churn beyond the rename).
```

```swift
// Sources/Hubber/Core/Connection.swift
@MainActor
final class Connection: ObservableObject, Identifiable {
    let id: ConnectionID
    @Published var authState: HubberAuthState = .restoring
    @Published private(set) var data = HubberData(incoming: [], outgoing: [], drafts: [])
    @Published var incomingError, outgoingError, draftsError, pullRequestRefreshError: String?
    @Published var rateLimitedUntil: Date?
    var notificationBaseline: ReviewSnapshot?

    let provider: any CodeHostProvider
    let authService: any GitHubDeviceFlowServicing
    let tokenStore: any GitHubTokenStoring
    let snapshotStore: SnapshotStore
    let scheduler: RefreshScheduler
    // moved from HubberStore, scoped to this connection:
    func restoreSession(); func startSignIn(policy: ProviderAccessPolicy)
    func signOut() async; func refreshNow()
    func refreshPullRequestsFromGitHub() async -> TabSuccesses?   // nil if it bailed
    var signedInLogin: String? { ... }
}
```

```swift
// Sources/Hubber/Core/ConnectionAggregator.swift
enum ConnectionAggregator {
    /// Union across connections; dedup incoming by id keeping earliest sloClockStart,
    /// outgoing/drafts by id keeping first. Deterministic sort.
    static func aggregate(_ datas: [HubberData]) -> HubberData
    /// Union of baselines for the single cross-connection notification diff (dedup by id).
    static func mergedBaseline(_ baselines: [ReviewSnapshot]) -> ReviewSnapshot
}
```

```swift
// Sources/Hubber/GitHubAuth.swift — HubberStore becomes the coordinator
@MainActor final class HubberStore: ObservableObject {
    @Published private(set) var connections: [Connection]
    var primaryConnection: Connection? { connections.first }
    // forwarded single-connection surface the existing views already use:
    var authState: HubberAuthState { primaryConnection?.authState ?? .signedOut }
    var data: HubberData { ConnectionAggregator.aggregate(connections.map(\.data)) }
    // errors/refresh-state forward from primaryConnection; settings/telemetry stay shared.
    func addConnection(_ id: ConnectionID)        // builds keyed stores + scheduler
    func removeConnection(_ id: ConnectionID) async
    func restoreAllConnections()                  // from registry (+ legacy migration)
}
```

> **`@Published var data` removal:** today views read `store.data` (a stored `@Published`). Replace with a computed aggregate plus an explicit `objectWillChange.send()` (or a small `@Published private(set) var aggregatedData` recomputed whenever any connection publishes). Use a Combine merge of the connections' `objectWillChange` → recompute. Keep the public name `data` so views don't change.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/Core/ConnectionID.swift` | Deterministic identity + `slug` |
| Create | `Sources/Hubber/Core/Connection.swift` | Per-connection state + lifecycle (restore/sign-in/refresh/sign-out) |
| Create | `Sources/Hubber/Core/ConnectionAggregator.swift` | Pure union + dedup + merged baseline |
| Create | `Sources/Hubber/Core/ConnectionRegistry.swift` | Persist/list `[ConnectionID]` in UserDefaults; legacy migration |
| Modify | `Sources/Hubber/GitHubAuth.swift` | Keyed `GitHubKeychainTokenStore(account:)`; `CodeHostAuthServicing`/`GitHubDeviceFlowServicing`; `HubberStore` → coordinator over `[Connection]` |
| Modify | `Sources/Hubber/GitHub/HubberStoreTabs.swift` | Move per-tab fetch onto `Connection` (operates on its own `data`/errors) |
| Modify | `Sources/Hubber/GitHub/HubberStoreNotifications.swift` | Coordinator diff over aggregated data vs merged baseline; per-connection baseline write-back |
| Modify | `Sources/Hubber/Notifications/SnapshotStore.swift` | `init(connectionID:)` + `delete()` + `legacySnapshotURL` |
| Modify | `Sources/Hubber/HubberPopoverView.swift` | Bind to forwarded surface only where stored→computed changes force it (no UX change) |
| Modify | `Sources/Hubber/main.swift` | Build coordinator; `restoreAllConnections()` at launch |
| Create | `Tests/HubberTests/ConnectionIDTests.swift` | slug/equality/determinism |
| Create | `Tests/HubberTests/TokenStoreIsolationTests.swift` | MC-TOKEN-01/02 |
| Create | `Tests/HubberTests/ConnectionAggregatorTests.swift` | MC-AGG-01..05, MC-BADGE-01..04 |
| Create | `Tests/HubberTests/MultiConnectionStoreTests.swift` | MC-AUTH-02/04, MC-SIGNOUT-02/03, MC-SCHED-02, MC-ERR-02, MC-MDM-01 |
| Create | `Tests/HubberTests/MultiConnectionNotificationTests.swift` | MC-NOTIF-01/02/03/04 |
| Modify | `Tests/HubberTests/SnapshotStoreTests.swift` | per-connection path uniqueness (MC-NOTIF-01) + migration |
| Modify | `Tests/HubberTests/HubberStoreRestoreSessionTests.swift` | `SpyTokenStore` keyed; single-connection restore still green |

---

## Tasks

### Task 1 — `ConnectionID` (TDD, pure)
Create `ConnectionID` per the contract. `slug` lowercases and replaces any char outside `[a-z0-9._-]` with `-`. **Tests (`ConnectionIDTests`):** equal IDs from mixed-case inputs; stable `slug`; `gitHubDotCom(login:)` helper. Commit: `feat(m6): deterministic ConnectionID (provider,host,login) (#81)`.

### Task 2 — Keyed Keychain token store + migration (TDD) — landmine #1
Add `init(account:)` to `GitHubKeychainTokenStore` (keep `service` constant). Add `GitHubTokenStore.makeStore(for: ConnectionID)`. Migration helper: if the registry is empty and a legacy item exists at `account = legacyAccount`, read it, derive `ConnectionID.gitHubDotCom(login:)` from the token's cached `login`, write it under the new account, delete the legacy item. **Tests (`TokenStoreIsolationTests`, using `SpyTokenStore` keyed by account):** two connections' `save()` write distinct `(service, account)`; `load()` for A never returns B's token (MC-TOKEN-01); `delete()` on A leaves B intact (MC-TOKEN-02). Commit: `feat(m6): per-connection Keychain key derivation + legacy migration (#81)`.

### Task 3 — Per-connection `SnapshotStore` + migration (TDD) — landmine #2
Add `init(connectionID:)` (path `notification-snapshot-<slug>.json`), `delete()`, and `legacySnapshotURL`. Migration: if the new path is absent and `legacySnapshotURL` exists, move it to the primary connection's path. **Tests (`SnapshotStoreTests`):** two connection IDs → two distinct paths; writing A does not touch B (MC-NOTIF-01); `delete()` removes only A's file; migration renames legacy once. Commit: `feat(m6): per-connection SnapshotStore paths + delete + migration (#81)`.

### Task 4 — Auth seam split (TDD, rename) 
Introduce `CodeHostAuthServicing` (generic) + `GitHubDeviceFlowServicing` (adds device flow); make `GitHubAuthServicing` an alias for the latter; `GitHubAuthService` and `SpyGitHubAuthService` conform unchanged. **Tests:** existing auth tests stay green; add a compile-level conformance assertion. Commit: `refactor(m6): CodeHostAuthServicing seam (GitHub conforms; GitLab/#60 later) (#81)`.

### Task 5 — Pure `ConnectionAggregator` (TDD) 
Implement `aggregate` (union; dedup incoming by id keeping earliest `sloClockStart`; outgoing/drafts by id keeping first; deterministic sort: incoming by `sloClockStart` asc, outgoing by `updatedAgoHours` asc, drafts by `updatedAt` desc) and `mergedBaseline` (union of `incomingIDs`; merge `outgoing` dicts, keep first per id). **Tests (`ConnectionAggregatorTests`):** MC-AGG-01 (union count 5), MC-AGG-02 (dup id once, earliest SLO kept), MC-AGG-03 (outgoing sort), MC-AGG-04 (drafts dedup), MC-AGG-05 (one connection's items survive when the other contributes none), MC-BADGE-01..04 (attention count / isAllGreen over aggregated data). Commit: `feat(m6): ConnectionAggregator union+dedup+mergedBaseline (#81)`.

### Task 6 — Extract `Connection` (TDD) — landmine #3 (core refactor)
Create `Connection`. Move from `HubberStore` into it, scoped to one account: `restoreSession`, `startSignIn(policy:)`, `cancelSignIn`, `signOut`, the per-tab fetch (`HubberStoreTabs.swift` methods rebased onto `self.data`/`self.{incoming,outgoing,drafts}Error`), `refreshPullRequestsFromGitHub`, `handleRefreshError`, `freshStoredToken`, its own `RefreshScheduler` and `authTask`. Each `Connection` takes the **shared** `settings`/`telemetry` and a **per-connection** `tokenStore`/`snapshotStore`/`provider`. **Tests (`MultiConnectionStoreTests`):** MC-AUTH-02 (second account reaches `.signedIn` without disturbing the first), MC-AUTH-04 (both restore; one expired → `.sessionExpired`, other `.signedIn`), MC-SCHED-02 (rate-limit on A via `ControlledSleeper`/spy does not change B's cadence), MC-ERR-02 (`rateLimitedUntil` set on A only), MC-MDM-01 (`startSignIn` under `allowPersonalGitHub=false` never calls `startDeviceFlow`). Commit: `feat(m6): extract per-connection Connection (token/scheduler/authTask isolation) (#81)`.

### Task 7 — `HubberStore` coordinator + registry + sign-out isolation (TDD) 
Reshape `HubberStore` to hold `@Published private(set) var connections: [Connection]` and the shared `settings`/`telemetry`/`notificationCoordinator`. Forward the single-connection surface (`authState`, errors, `usernameDisplay`, `canRefreshPullRequests`, `isAuthenticating`) from `primaryConnection`; expose `data` as the recomputed `ConnectionAggregator.aggregate(...)` (Combine-merge connections' `objectWillChange` → republish). Add `ConnectionRegistry` (UserDefaults `hubber.connections` = encoded `[ConnectionID]`), `addConnection`/`removeConnection`, and `restoreAllConnections()` (registry → connections, running the Task-2/3 migrations when the registry is empty). `signOut()` and `removeConnection` touch only the target connection (its `tokenStore.delete()`, `snapshotStore.delete()`, `provider` `invalidateAll()`, `scheduler.stop()`). **Tests (`MultiConnectionStoreTests`):** MC-SIGNOUT-02 (`invalidateAll` only on A's provider — assert via a spy `CodeHostCacheInvalidating` wrapper), MC-SIGNOUT-03 (only A's scheduler stops; B keeps ticking via `ControlledSleeper`), and that single-connection `restoreAllConnections()` matches today's `restoreSession` behavior (extend `HubberStoreRestoreSessionTests`). Commit: `feat(m6): HubberStore coordinator over [Connection] + registry + sign-out isolation (#81)`.

### Task 8 — Cross-connection notification diff (TDD) 
Rework `HubberStoreNotifications.swift`: after any connection's refresh completes, build the diff input as `ConnectionAggregator.aggregate(connections.map(\.data))` vs `ConnectionAggregator.mergedBaseline(connections.compactMap(\.notificationBaseline))`, run a **single** `notificationCoordinator.processRefresh(...)`, then have **each** connection advance and persist its own baseline file (reusing the existing succeeded-tabs-only logic). **Tests (`MultiConnectionNotificationTests`):** MC-NOTIF-02 (new `pr-A1` on A fires once; unchanged `pr-B1` on B silent), MC-NOTIF-03 (both baselines match current → relaunch fires nothing), MC-NOTIF-04 (same PR approved under both accounts → exactly one `reviewApproved`), and the MC-AGG-02 regression (duplicate incoming id never double-fires `newReview`). Commit: `feat(m6): cross-connection notification diff over aggregated data + merged baseline (#81)`.

### Task 9 — View/main wiring + green sweep (no UX change) 
Update `HubberPopoverView.swift`/`main.swift` only as needed for the stored→computed `data` change and `restoreAllConnections()`. Run the full suite + lint + format; fix any single-connection regressions. **Verify:** `swift build` clean, `swift test` all green, `make lint` 0, `make format` idempotent; launch the app once signed into one account → identical behavior to pre-refactor. Commit: `feat(m6): wire coordinator into views + launch; green sweep (#81)`.

---

## Acceptance (whole PR — Phase-1 gate, `docs/qa/2026-06-16-multi-connection-test-plan.md`)
- `swift build` clean; `swift test` all pass (existing + new); `make lint` 0; `make format` idempotent.
- These Phase-1 stories are covered by passing tests: **MC-TOKEN-01/02/03/04, MC-AUTH-02/04, MC-NOTIF-01/02/03(+04), MC-SIGNOUT-02/03, MC-SCHED-02, MC-AGG-02/05, MC-ERR-02, MC-MDM-01.** (Token-03/04 refresh-scoping ride Task 6.)
- Single-connection behavior is byte-for-byte unchanged in the UI; legacy token + snapshot migrate with no notification storm and no lost session.
- Open PR → main with `Closes #81` and `Refs #80`; **watch CI green on `macos-26` before squash-merge.**

## Self-Review Checklist
- [ ] No constant Keychain `account` remains; each connection's `(service, account)` is distinct; legacy item migrated then deleted
- [ ] Each connection has its own `SnapshotStore` file; `delete()` on sign-out removes only that file; legacy snapshot migrated once
- [ ] `HubberStore` holds `[Connection]`; per-connection `authTask`/`scheduler`/`rateLimitedUntil` — no shared single-identity state left
- [ ] `data` aggregates 1..N connections with dedup by id (earliest SLO for incoming); partial failure keeps last-good + per-connection error
- [ ] Exactly one notification per event across connections (no cross-account double-fire); no re-fire on relaunch
- [ ] `signOut`/`removeConnection` never touch another connection's token/cache/snapshot/scheduler
- [ ] `CodeHostAuthServicing` seam present; device flow stays GitHub-specific; GitLab PAT path explicitly deferred to #60
- [ ] Single-connection UI + restore behavior identical to pre-refactor (no view UX change)
- [ ] `UNUserNotificationCenter` use still guarded for the bundle-less xctest host
